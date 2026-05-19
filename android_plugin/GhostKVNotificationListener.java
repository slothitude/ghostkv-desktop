package com.slothitude.ghostkv;

import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import android.os.Bundle;
import android.util.Log;

import java.util.ArrayList;

public class GhostKVNotificationListener extends NotificationListenerService {

    private static final String TAG = "GhostKVNotifications";
    private static final ArrayList<String> _cachedNotifications = new ArrayList<>();
    private static boolean _connected = false;

    @Override
    public void onListenerConnected() {
        super.onListenerConnected();
        _connected = true;
        Log.i(TAG, "Notification listener connected");
        refreshNotifications();
    }

    @Override
    public void onListenerDisconnected() {
        super.onListenerDisconnected();
        _connected = false;
        Log.i(TAG, "Notification listener disconnected");
    }

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        refreshNotifications();
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        refreshNotifications();
    }

    private void refreshNotifications() {
        StatusBarNotification[] notifications = getActiveNotifications();
        synchronized (_cachedNotifications) {
            _cachedNotifications.clear();
            for (StatusBarNotification sbn : notifications) {
                Bundle extras = sbn.getNotification().extras;
                String title = extras.getString("android.title", "");
                CharSequence textSeq = extras.getCharSequence("android.text");
                String text = textSeq != null ? textSeq.toString() : "";
                String pkg = sbn.getPackageName();
                _cachedNotifications.add(
                    "{\"app\":\"" + pkg.replace("\"", "'")
                    + "\",\"title\":\"" + title.replace("\"", "'")
                    + "\",\"text\":\"" + text.replace("\"", "'").replace("\n", " ")
                    + "\"}");
            }
        }
    }

    public static boolean isConnected() {
        return _connected;
    }

    public static String getCachedNotificationsJson() {
        synchronized (_cachedNotifications) {
            StringBuilder sb = new StringBuilder("[");
            for (int i = 0; i < _cachedNotifications.size(); i++) {
                if (i > 0) sb.append(",");
                sb.append(_cachedNotifications.get(i));
            }
            sb.append("]");
            return sb.toString();
        }
    }
}
