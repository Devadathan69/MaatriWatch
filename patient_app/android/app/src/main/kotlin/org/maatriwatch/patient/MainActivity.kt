package org.maatriwatch.patient

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel("guardian_sos", "Guardian SOS requests", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Urgent support requests from linked patients"
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            })
            manager.createNotificationChannel(NotificationChannel("maatri_reminders", "MaatriCare reminders", NotificationManager.IMPORTANCE_DEFAULT))
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "maatriwatch/notifications").setMethodCallHandler { call, result ->
            if (call.method != "show") { result.notImplemented(); return@setMethodCallHandler }
            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                result.success(null); return@setMethodCallHandler
            }
            val guardian = call.argument<Boolean>("guardian") == true
            val opaqueId = call.argument<String>("id") ?: "reminder"
            val channel = if (guardian) "guardian_sos" else "maatri_reminders"
            val open = PendingIntent.getActivity(this, opaqueId.hashCode(), Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, channel) else Notification.Builder(this)
            manager.notify(opaqueId.hashCode(), builder.setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(if (guardian) "MaatriWatch SOS" else "A gentle MaatriCare reminder")
                .setContentText(if (guardian) "Someone linked to you has requested urgent help. Open MaatriWatch now." else "Open MaatriWatch to see your reminder.")
                .setContentIntent(open).setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPriority(if (guardian) Notification.PRIORITY_HIGH else Notification.PRIORITY_DEFAULT).build())
            result.success(null)
        }
    }
}
