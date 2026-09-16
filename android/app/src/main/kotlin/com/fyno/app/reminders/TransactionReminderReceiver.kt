package com.fyno.app.reminders

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.fyno.app.MainActivity
import com.fyno.app.R
import java.text.NumberFormat
import java.util.Locale

class TransactionReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            TransactionReminderScheduler.rescheduleAll(context)
            return
        }

        val id = intent.getIntExtra("notification_id", -1)
        if (id < 0) return
        createChannel(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val bank = intent.getStringExtra("bank_name").orEmpty()
        val amount = if (intent.hasExtra("amount")) {
            NumberFormat.getCurrencyInstance(Locale.forLanguageTag("pt-BR"))
                .format(intent.getDoubleExtra("amount", 0.0))
        } else null
        val isFinancialCheckIn = id == 900000
        val detail = if (isFinancialCheckIn) {
            "Reserve alguns minutos para registrar seus gastos, conferir os cartões e colocar as contas em dia."
        } else {
            listOfNotNull(
                amount?.let { "Movimentação de $it" },
                bank.takeIf(String::isNotBlank)?.let { "detectada no $it" },
            ).joinToString(" ").ifBlank { "Você deixou uma transação para revisar." }
        }

        val openApp = PendingIntent.getActivity(
            context,
            id,
            Intent(context, MainActivity::class.java)
                .putExtra("open_notification_id", id)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(if (isFinancialCheckIn) "Hora de cuidar das suas finanças" else "Hora de organizar sua transação")
            .setContentText(detail)
            .setStyle(NotificationCompat.BigTextStyle().bigText(
                if (isFinancialCheckIn) "$detail Abra o Fyno para começar."
                else "$detail Abra o Fyno para revisar, categorizar ou descartar."
            ))
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(context).notify(BASE_NOTIFICATION_ID + id, notification)
        TransactionReminderScheduler.markDelivered(context, id)
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Lembretes de transações",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Lembra você de revisar movimentações deixadas para depois."
            },
        )
    }

    companion object {
        private const val CHANNEL_ID = "fyno_transaction_reminders"
        private const val BASE_NOTIFICATION_ID = 41_000
    }
}
