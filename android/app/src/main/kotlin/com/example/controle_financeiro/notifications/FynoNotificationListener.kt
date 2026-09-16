package com.example.controle_financeiro.notifications

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

class FynoNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnectedNow = true
        diagnostics().edit()
            .putBoolean("listener_connected", true)
            .putLong("last_connected_at_ms", System.currentTimeMillis())
            .apply()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Versões antigas do Fyno declaravam "alerting" no manifesto e
            // bloqueavam "silent". Migra o padrão para todos os tipos; o usuário
            // ainda pode alterar esse filtro nas configurações do Android.
            val allTypes = FLAG_FILTER_TYPE_CONVERSATIONS or
                FLAG_FILTER_TYPE_ALERTING or
                FLAG_FILTER_TYPE_SILENT or
                FLAG_FILTER_TYPE_ONGOING
            try { migrateNotificationFilter(allTypes, null) } catch (_: Throwable) {}
        }

        // Fabricantes como Xiaomi/POCO podem suspender e depois religar o
        // listener. Os callbacks ocorridos durante esse intervalo se perdem,
        // então também examinamos as notificações que continuam ativas quando
        // o Android reconecta o serviço.
        scanActiveNotifications()
        // HyperOS frequentemente conecta o listener antes de liberar a lista.
        // Repetir a leitura recupera alertas recebidos enquanto o processo estava suspenso.
        Handler(Looper.getMainLooper()).postDelayed(::scanActiveNotifications, 1_500)
        Handler(Looper.getMainLooper()).postDelayed(::scanActiveNotifications, 5_000)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isConnectedNow = false
        diagnostics().edit().putBoolean("listener_connected", false).apply()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val component = ComponentName(this, FynoNotificationListener::class.java)
            try { requestRebind(component) } catch (_: Throwable) {}
            Handler(Looper.getMainLooper()).postDelayed({
                try { requestRebind(component) } catch (_: Throwable) {}
            }, 1200)
        }
    }

    override fun onDestroy() {
        isConnectedNow = false
        diagnostics().edit().putBoolean("listener_connected", false).apply()
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        processNotification(sbn)
    }

    private fun processNotification(sbn: StatusBarNotification) {
        try {
            if (sbn.packageName == packageName) return
            val prefs = getSharedPreferences("FynoNotifSettings", Context.MODE_PRIVATE)
            recordObserved(prefs, sbn.packageName)
            if (!prefs.getBoolean("capture_enabled", false)) return

            val allowed = JSONArray(prefs.getString("allowed_packages", "[]") ?: "[]")
            if (allowed.length() == 0) return
            var packageAllowed = false
            for (index in 0 until allowed.length()) {
                if (sbn.packageName == allowed.optString(index)) {
                    packageAllowed = true
                    break
                }
            }
            if (!packageAllowed) return
            val extras = sbn.notification.extras ?: run {
                recordRejected(prefs, "Notificação sem conteúdo legível")
                return
            }
            val parts = linkedSetOf<String>()
            listOf(
                Notification.EXTRA_TITLE,
                Notification.EXTRA_TITLE_BIG,
                Notification.EXTRA_TEXT,
                Notification.EXTRA_BIG_TEXT,
                Notification.EXTRA_SUB_TEXT,
                Notification.EXTRA_SUMMARY_TEXT,
                Notification.EXTRA_INFO_TEXT,
            ).forEach { key ->
                extras.getCharSequence(key)?.toString()?.trim()
                    ?.takeIf(String::isNotEmpty)?.let(parts::add)
            }
            extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
                ?.map { it.toString().trim() }
                ?.filter(String::isNotEmpty)
                ?.forEach(parts::add)

            // Alguns bancos colocam o texto útil somente na versão pública da
            // notificação (por exemplo, quando há conteúdo sensível na tela).
            sbn.notification.publicVersion?.extras?.let { publicExtras ->
                listOf(
                    Notification.EXTRA_TITLE,
                    Notification.EXTRA_TEXT,
                    Notification.EXTRA_BIG_TEXT,
                    Notification.EXTRA_SUB_TEXT,
                    Notification.EXTRA_SUMMARY_TEXT,
                    Notification.EXTRA_INFO_TEXT,
                ).forEach { key ->
                    publicExtras.getCharSequence(key)?.toString()?.trim()
                        ?.takeIf(String::isNotEmpty)?.let(parts::add)
                }
            }

            val title = extras.getCharSequence(Notification.EXTRA_TITLE)
                ?.toString()?.trim().orEmpty().take(160)
            val body = parts.joinToString(" • ").take(600)
            if (body.isBlank()) {
                recordRejected(prefs, "Notificação sem texto legível")
                return
            }
            // Bancos costumam reutilizar uma notificação agrupada, misturando a
            // compra atual com linhas antigas de login, oferta ou saldo. Analisar
            // tudo junto fazia um termo sensível antigo invalidar a compra real.
            // Primeiro tentamos cada trecho com o título e só depois o bloco unido.
            val candidates = linkedSetOf<String>()
            parts.forEach { part ->
                candidates.add(if (title.isBlank() || part == title) part else "$title • $part")
                candidates.add(part)
            }
            candidates.add(body)
            val match = candidates.asSequence()
                .mapNotNull { candidate ->
                    TransactionNotificationParser.parse(candidate)?.let { candidate to it }
                }
                .firstOrNull()
            val parsed = match?.second ?: run {
                recordRejected(prefs, "Alerta bancário sem transação reconhecida")
                Log.d(TAG, "Rejeitada ${sbn.packageName}: sem transação reconhecida")
                return
            }
            val matchedBody = match.first.take(600)
            val minuteBucket = sbn.postTime / 60_000L
            val key = fingerprint(
                "${sbn.packageName}|${parsed.amount}|${parsed.isIncome}|$matchedBody|$minuteBucket",
            )

            val json = JSONObject()
                .put("notif_key", key)
                .put("package_name", sbn.packageName)
                .put("title", title)
                .put("text", matchedBody)
                .put("posted_at_ms", sbn.postTime)
                .put("parsed_amount", parsed.amount)
                .put("parsed_is_income", parsed.isIncome ?: JSONObject.NULL)
                .put("parsed_method", parsed.method)

            if (NotificationBufferStore.append(this, json.toString())) {
                Log.i(TAG, "Transação capturada de ${sbn.packageName}")
                prefs.edit()
                    .putLong("last_captured_at_ms", System.currentTimeMillis())
                    .putLong("captured_count", prefs.getLong("captured_count", 0L) + 1L)
                    .putString("last_rejection_reason", "")
                    .apply()
            }
        } catch (_: Throwable) {
            // Uma notificação malformada nunca deve afetar o restante do app.
            diagnostics().edit()
                .putString("last_rejection_reason", "Falha ao processar a notificação")
                .apply()
        }
    }

    private fun diagnostics() =
        getSharedPreferences("FynoNotifSettings", Context.MODE_PRIVATE)

    private fun scanActiveNotifications() {
        try {
            activeNotifications?.forEach(::processNotification)
        } catch (error: Throwable) {
            diagnostics().edit()
                .putString("last_rejection_reason", "Android ainda não liberou as notificações ativas")
                .apply()
            Log.d(TAG, "Lista de notificações ainda indisponível", error)
        }
    }

    private fun recordObserved(prefs: android.content.SharedPreferences, packageName: String) {
        prefs.edit()
            .putLong("last_seen_at_ms", System.currentTimeMillis())
            .putString("last_seen_package", packageName)
            .putLong("observed_count", prefs.getLong("observed_count", 0L) + 1L)
            .apply()
    }

    private fun recordRejected(prefs: android.content.SharedPreferences, reason: String) {
        prefs.edit().putString("last_rejection_reason", reason).apply()
    }

    private fun fingerprint(value: String): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val TAG = "FynoNotification"

        /**
         * Estado real desta instância no processo atual. O valor salvo em
         * SharedPreferences pode ficar positivo quando o HyperOS mata o
         * processo sem entregar onListenerDisconnected().
         */
        @Volatile
        var isConnectedNow: Boolean = false
            private set
    }
}
