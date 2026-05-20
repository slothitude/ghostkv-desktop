package com.slothitude.ghostkv;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

import androidx.core.app.NotificationCompat;

/**
 * Foreground service that keeps GhostKV alive in the background
 * so the Telegram bot can continue polling for messages.
 */
public class GhostKVBgService extends Service {

    private static final int NOTIFICATION_ID = 1001;
    private static final String CHANNEL_ID = "ghostkv_bg";
    private PowerManager.WakeLock _wakeLock;

    @Override
    public void onCreate() {
        super.onCreate();

        // Create notification channel
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "GhostKV Background", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("GhostKV is running in background");
            nm.createNotificationChannel(channel);
        }

        // Start as foreground with notification
        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("GhostKV")
            .setContentText("Telegram bot active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build();

        startForeground(NOTIFICATION_ID, notification);

        // Acquire partial wake lock to keep CPU alive
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (pm != null) {
            _wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GhostKV::BgPoll");
            _wakeLock.acquire();
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        if (_wakeLock != null && _wakeLock.isHeld()) {
            _wakeLock.release();
            _wakeLock = null;
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
