package com.onyx.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.preference.PreferenceManager

class InstagramNotificationListener : NotificationListenerService() {

    companion object {
        private const val INSTAGRAM_PACKAGE = "com.instagram.android"
        private const val CHANNEL_MESSAGES = "onyx_messages"
        private const val CHANNEL_CALLS = "onyx_calls"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)
            
            val messageChannel = NotificationChannel(
                CHANNEL_MESSAGES,
                "Messages Instagram",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications de messages via Onyx"
                enableVibration(true)
            }
            
            val callChannel = NotificationChannel(
                CHANNEL_CALLS,
                "Appels Instagram",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications d'appels via Onyx"
                enableVibration(true)
                setSound(android.provider.Settings.System.DEFAULT_RINGTONE_URI, null)
            }
            
            notificationManager.createNotificationChannel(messageChannel)
            notificationManager.createNotificationChannel(callChannel)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        
        // Only intercept Instagram notifications
        if (sbn.packageName != INSTAGRAM_PACKAGE) return
        
        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return
        
        val title = extras.getString(Notification.EXTRA_TITLE) ?: return
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        
        // Detect notification type
        val isCall = isCallNotification(title, text, notification)
        val isMessage = isMessageNotification(title, text)
        
        if (isCall) {
            showOnyxCallNotification(title, text, sbn.id)
        } else if (isMessage) {
            showOnyxMessageNotification(title, text, sbn.id)
        }
    }

    private fun isCallNotification(title: String, text: String, notification: Notification): Boolean {
        val lowerTitle = title.lowercase()
        val lowerText = text.lowercase()
        
        // Check for call-related keywords
        val callKeywords = listOf(
            "appel", "call", "calling", "video", "vidéo",
            "incoming", "entrant", "ringing"
        )
        
        // Check if notification has call actions (answer/decline)
        val hasCallActions = notification.actions?.any { action ->
            val actionTitle = action.title?.toString()?.lowercase() ?: ""
            actionTitle.contains("answer") || actionTitle.contains("decline") ||
            actionTitle.contains("répondre") || actionTitle.contains("refuser")
        } ?: false
        
        return hasCallActions || callKeywords.any { keyword ->
            lowerTitle.contains(keyword) || lowerText.contains(keyword)
        }
    }

    private fun isMessageNotification(title: String, text: String): Boolean {
        // Most Instagram notifications that aren't calls are messages/DMs
        val lowerText = text.lowercase()
        val messageKeywords = listOf(
            "message", "sent", "envoyé", "replied", "répondu",
            "mentioned", "mentionné", "dm", "direct"
        )
        
        return messageKeywords.any { lowerText.contains(it) } || text.isNotEmpty()
    }

    private fun showOnyxMessageNotification(title: String, text: String, originalId: Int) {
        val prefs = PreferenceManager.getDefaultSharedPreferences(this)
        
        // Create intent to open Onyx messages
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("target_url", "https://www.instagram.com/direct/inbox/")
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            originalId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_MESSAGES)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .build()

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(originalId + 10000, notification)
    }

    private fun showOnyxCallNotification(title: String, text: String, originalId: Int) {
        val prefs = PreferenceManager.getDefaultSharedPreferences(this)
        val openInOnyx = prefs.getString("open_calls_in", "onyx") == "onyx"
        
        val intent = if (openInOnyx) {
            // Open Onyx to messages (where calls appear)
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("target_url", "https://www.instagram.com/direct/inbox/")
            }
        } else {
            // Open Instagram directly
            packageManager.getLaunchIntentForPackage(INSTAGRAM_PACKAGE)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            } ?: Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra("target_url", "https://www.instagram.com/direct/inbox/")
            }
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            originalId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_CALLS)
            .setSmallIcon(R.drawable.ic_call)
            .setContentTitle("📞 $title")
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .build()

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(originalId + 20000, notification)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn ?: return
        
        if (sbn.packageName == INSTAGRAM_PACKAGE) {
            // Remove our corresponding notification when Instagram's is removed
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.cancel(sbn.id + 10000)
            notificationManager.cancel(sbn.id + 20000)
        }
    }
}
