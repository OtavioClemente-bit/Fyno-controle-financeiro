package com.fyno.app.reminders

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONObject

object TransactionReminderScheduler {
    private const val PREFS = "FynoTransactionReminders"
    private const val PREFIX = "reminder_"

    fun schedule(
        context: Context,
        notificationId: Int,
        atMs: Long,
        bankName: String,
        amount: Double?,
    ): Boolean {
        if (atMs <= System.currentTimeMillis()) return false
        val payload = JSONObject()
            .put("notification_id", notificationId)
            .put("at_ms", atMs)
            .put("bank_name", bankName)
            .put("amount", amount ?: JSONObject.NULL)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("$PREFIX$notificationId", payload.toString())
            .apply()
        return scheduleAlarm(context, notificationId, atMs, bankName, amount)
    }

    fun cancel(context: Context, notificationId: Int) {
        alarmManager(context).cancel(pendingIntent(context, notificationId, null))
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove("$PREFIX$notificationId")
            .apply()
    }

    fun rescheduleAll(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.all.forEach { (key, value) ->
            if (!key.startsWith(PREFIX) || value !is String) return@forEach
            try {
                val payload = JSONObject(value)
                val id = payload.getInt("notification_id")
                val atMs = payload.getLong("at_ms")
                val bank = payload.optString("bank_name")
                val amount = if (payload.isNull("amount")) null else payload.optDouble("amount")
                if (atMs > System.currentTimeMillis()) {
                    scheduleAlarm(context, id, atMs, bank, amount)
                } else {
                    // Lembretes vencidos durante o aparelho desligado aparecem logo após iniciar.
                    scheduleAlarm(context, id, System.currentTimeMillis() + 5_000L, bank, amount)
                }
            } catch (_: Throwable) {
                prefs.edit().remove(key).apply()
            }
        }
    }

    fun markDelivered(context: Context, notificationId: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove("$PREFIX$notificationId")
            .apply()
    }

    private fun scheduleAlarm(
        context: Context,
        notificationId: Int,
        atMs: Long,
        bankName: String,
        amount: Double?,
    ): Boolean {
        return try {
            val intent = Intent(context, TransactionReminderReceiver::class.java)
                .putExtra("notification_id", notificationId)
                .putExtra("bank_name", bankName)
            if (amount != null) intent.putExtra("amount", amount)
            alarmManager(context).setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                atMs,
                pendingIntent(context, notificationId, intent),
            )
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun pendingIntent(
        context: Context,
        notificationId: Int,
        source: Intent?,
    ): PendingIntent {
        val intent = source ?: Intent(context, TransactionReminderReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun alarmManager(context: Context) =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
}
