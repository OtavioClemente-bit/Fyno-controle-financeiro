package com.fyno.app

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import com.example.controle_financeiro.notifications.NotificationBufferStore
import com.example.controle_financeiro.notifications.FynoNotificationListener
import com.fyno.app.reminders.TransactionReminderScheduler

class MainActivity : FlutterActivity() {

    private val CHANNEL_ACCESS = "notif_access"
    // Canal adicional para buffer de notificações capturadas com o app fechado.
    private val CHANNEL_BUFFER = "fyno/notification_buffer"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_ACCESS)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNotificationListenerEnabled" -> result.success(isNotificationListenerEnabled())
                    "openNotificationListenerSettings" -> {
                        openNotificationListenerSettings()
                        result.success(true)
                    }
                    "isCaptureEnabled" -> {
                        val prefs = getSharedPreferences("FynoNotifSettings", MODE_PRIVATE)
                        result.success(prefs.getBoolean("capture_enabled", false))
                    }
                    "setCaptureEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val prefs = getSharedPreferences("FynoNotifSettings", MODE_PRIVATE)
                        prefs.edit().putBoolean("capture_enabled", enabled).apply()
                        if (!enabled) {
                            NotificationBufferStore.clear(applicationContext)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            // Recupera listeners que o fabricante desconectou enquanto
                            // o app estava em economia de bateria ou após uma atualização.
                            try {
                                NotificationListenerService.requestRebind(
                                    ComponentName(
                                        applicationContext,
                                        FynoNotificationListener::class.java,
                                    ),
                                )
                            } catch (_: Throwable) {}
                        }
                        result.success(true)
                    }
                    "requestNotificationRebind" -> {
                        requestNotificationRebind()
                        result.success(true)
                    }
                    "hasBackgroundStartupSettings" -> {
                        result.success(hasBackgroundStartupSettings())
                    }
                    "openBackgroundStartupSettings" -> {
                        result.success(openBackgroundStartupSettings())
                    }
                    "getNotificationDiagnostics" -> {
                        result.success(getNotificationDiagnostics())
                    }
                    "getInstalledPackages" -> {
                        val candidates = call.argument<List<String>>("packages") ?: emptyList()
                        result.success(candidates.filter(::isPackageInstalled))
                    }
                    "runNotificationSelfTest" -> {
                        result.success(runNotificationSelfTest())
                    }
                    "scheduleReviewReminder" -> {
                        val notificationId = call.argument<Number>("notificationId")?.toInt()
                        val atMs = call.argument<Number>("atMs")?.toLong()
                        if (notificationId == null || atMs == null) {
                            result.success(false)
                        } else {
                            result.success(
                                TransactionReminderScheduler.schedule(
                                    context = applicationContext,
                                    notificationId = notificationId,
                                    atMs = atMs,
                                    bankName = call.argument<String>("bankName").orEmpty(),
                                    amount = call.argument<Number>("amount")?.toDouble(),
                                ),
                            )
                        }
                    }
                    "cancelReviewReminder" -> {
                        val notificationId = call.argument<Number>("notificationId")?.toInt()
                        if (notificationId == null) {
                            result.success(false)
                        } else {
                            TransactionReminderScheduler.cancel(
                                applicationContext,
                                notificationId,
                            )
                            result.success(true)
                        }
                    }
                    "consumeLaunchedReminder" -> {
                        val reminderId = intent?.getIntExtra("open_notification_id", -1) ?: -1
                        intent?.removeExtra("open_notification_id")
                        result.success(reminderId.takeIf { it >= 0 })
                    }
                    else -> result.notImplemented()
                }
            }

        // Canal para configurar pacotes permitidos e consumir notificações capturadas no background.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_BUFFER)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAllowedPackages" -> {
                        // Lista vazia significa capturar nada, nunca "todos".
                        val list = call.argument<List<String>>("packages") ?: emptyList()
                        val prefs = getSharedPreferences("FynoNotifSettings", MODE_PRIVATE)
                        try {
                            val arr = JSONArray()
                            for (pkg in list) {
                                arr.put(pkg)
                            }
                            prefs.edit().putString("allowed_packages", arr.toString()).apply()
                            result.success(true)
                        } catch (_: Throwable) {
                            // falha silenciosa
                            result.success(false)
                        }
                    }
                    "drain" -> {
                        // Lê e remove notificações armazenadas no buffer nativo.
                        val lines = NotificationBufferStore.drain(applicationContext)
                        val outList = ArrayList<Map<String, Any?>>()
                        for (jsonString in lines) {
                            try {
                                val obj = JSONObject(jsonString)
                                val map = HashMap<String, Any?>()
                                val keys = obj.keys()
                                while (keys.hasNext()) {
                                    val key = keys.next()
                                    map[key] = if (obj.isNull(key)) null else obj.get(key)
                                }
                                outList.add(map)
                            } catch (_: Throwable) {
                                // ignora linhas inválidas
                            }
                        }
                        result.success(outList)
                    }
                    "clear" -> {
                        // Limpa o buffer de notificações.
                        NotificationBufferStore.clear(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openNotificationListenerSettings() {
        val listener = ComponentName(
            applicationContext,
            FynoNotificationListener::class.java,
        )
        val intents = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            intents += Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(
                    Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                    listener.flattenToString(),
                )
        }
        intents += Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)

        for (intent in intents) {
            try {
                if (intent.resolveActivity(packageManager) == null) continue
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return
            } catch (_: Throwable) {}
        }
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val expected = ComponentName(
            applicationContext,
            FynoNotificationListener::class.java,
        )
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        if (flat.isBlank()) return false

        val names = flat.split(":")
        for (name in names) {
            val cn = ComponentName.unflattenFromString(name) ?: continue
            if (TextUtils.equals(expected.packageName, cn.packageName) &&
                TextUtils.equals(expected.className, cn.className)
            ) return true
        }
        return false
    }

    private fun requestNotificationRebind() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        try {
            NotificationListenerService.requestRebind(
                ComponentName(applicationContext, FynoNotificationListener::class.java),
            )
        } catch (_: Throwable) {}
    }

    private fun hasBackgroundStartupSettings(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        return listOf(manufacturer, brand).any { value ->
            value.contains("xiaomi") ||
                value.contains("redmi") ||
                value.contains("poco")
        }
    }

    /**
     * Abre a lista de inicialização automática do HyperOS/MIUI. Não existe
     * uma API Android que conceda essa permissão: a decisão continua sendo do
     * usuário. Em outros aparelhos, abre os detalhes do Fyno como fallback.
     */
    private fun openBackgroundStartupSettings(): Boolean {
        val intents = mutableListOf<Intent>()
        if (hasBackgroundStartupSettings()) {
            intents += Intent("miui.intent.action.OP_AUTO_START")
                .addCategory(Intent.CATEGORY_DEFAULT)
            intents += Intent().setComponent(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                ),
            )
        }
        intents += Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        )

        for (intent in intents) {
            try {
                if (intent.resolveActivity(packageManager) == null) continue
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Throwable) {}
        }
        return false
    }

    private fun getNotificationDiagnostics(): Map<String, Any?> {
        val prefs = getSharedPreferences("FynoNotifSettings", MODE_PRIVATE)
        return mapOf(
            "permission_enabled" to isNotificationListenerEnabled(),
            "capture_enabled" to prefs.getBoolean("capture_enabled", false),
            // O valor persistido pode ficar obsoleto quando o fabricante mata
            // o processo. A variável estática representa o vínculo atual.
            "listener_connected" to FynoNotificationListener.isConnectedNow,
            "last_connected_at_ms" to prefs.getLong("last_connected_at_ms", 0L),
            "last_seen_at_ms" to prefs.getLong("last_seen_at_ms", 0L),
            "last_seen_package" to prefs.getString("last_seen_package", ""),
            "last_captured_at_ms" to prefs.getLong("last_captured_at_ms", 0L),
            "last_rejection_reason" to prefs.getString("last_rejection_reason", ""),
            "observed_count" to prefs.getLong("observed_count", 0L),
            "captured_count" to prefs.getLong("captured_count", 0L),
        )
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    /**
     * Valida o caminho nativo -> buffer -> Flutter sem simular uma notificação
     * bancária real. O item é rotulado como teste e sempre exige revisão.
     */
    private fun runNotificationSelfTest(): Boolean {
        val prefs = getSharedPreferences("FynoNotifSettings", MODE_PRIVATE)
        if (!prefs.getBoolean("capture_enabled", false)) return false
        val allowed = JSONArray(prefs.getString("allowed_packages", "[]") ?: "[]")
        val packageName = allowed.optString(0).takeIf(String::isNotBlank) ?: return false
        val now = System.currentTimeMillis()
        val json = JSONObject()
            .put("notif_key", "fyno-self-test-$now")
            .put("package_name", packageName)
            .put("title", "Teste de detecção do Fyno")
            .put("text", "Item de teste — não é uma transação real")
            .put("posted_at_ms", now)
            .put("parsed_amount", 0.01)
            .put("parsed_is_income", JSONObject.NULL)
            .put("parsed_method", "Outro")
        NotificationBufferStore.append(applicationContext, json.toString())
        prefs.edit()
            .putLong("last_captured_at_ms", now)
            .putLong("captured_count", prefs.getLong("captured_count", 0L) + 1L)
            .putString("last_rejection_reason", "")
            .apply()
        return true
    }

}
