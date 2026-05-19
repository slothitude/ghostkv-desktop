package com.slothitude.ghostkv;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.provider.AlarmClock;
import android.provider.ContactsContract;
import android.provider.MediaStore;
import android.speech.RecognizerIntent;
import android.speech.tts.TextToSpeech;
import android.telephony.SmsManager;
import android.widget.Toast;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * GhostKV Android Plugin — bridges Godot GDScript to Android system APIs.
 *
 * Exposes: execCommand, sendSMS, openCamera, openApp, openUrl, listApps,
 *          showToast, vibrate, isTermuxInstalled, getPythonPath
 */
public class GhostKVPlugin extends GodotPlugin {

    private static final int SMS_PERMISSION_CODE = 1001;
    private String pendingSmsPhone = "";
    private String pendingSmsMessage = "";
    private TextToSpeech _tts;
    private boolean _ttsReady = false;

    public GhostKVPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "GhostKVPlugin";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("command_completed", String.class, Integer.class));
        signals.add(new SignalInfo("sms_sent", String.class));
        signals.add(new SignalInfo("sms_failed", String.class));
        signals.add(new SignalInfo("permission_result", String.class, Boolean.TYPE));
        signals.add(new SignalInfo("location_received", Double.class, Double.class, Float.class));
        signals.add(new SignalInfo("speech_result", String.class));
        signals.add(new SignalInfo("speech_error", String.class));
        return signals;
    }

    // ── Shell execution ──────────────────────────────────────────────

    /**
     * Execute a shell command and return output.
     * Runs asynchronously — emits "command_completed" signal with (output, exitCode).
     */
    @UsedByGodot
    public void execCommand(String command) {
        new Thread(() -> {
            try {
                ProcessBuilder pb = new ProcessBuilder("sh", "-c", command);
                pb.redirectErrorStream(true);

                // If Termux is available, try to use its PATH
                String termuxPrefix = "/data/data/com.termux/files/usr/bin";
                File termuxBin = new File(termuxPrefix);
                if (termuxBin.exists()) {
                    String path = termuxPrefix + ":" + System.getenv("PATH");
                    pb.environment().put("PATH", path);
                    pb.environment().put("HOME", "/data/data/com.termux/files/home");
                    pb.environment().put("PREFIX", "/data/data/com.termux/files/usr");
                    pb.environment().put("LD_LIBRARY_PATH", "/data/data/com.termux/files/usr/lib");
                }

                Process process = pb.start();
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                StringBuilder output = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                }
                int exitCode = process.waitFor();
                emitSignal("command_completed", output.toString().trim(), exitCode);
            } catch (Exception e) {
                emitSignal("command_completed", "Error: " + e.getMessage(), -1);
            }
        }).start();
    }

    /**
     * Execute a command synchronously and return output string.
     * Blocks the calling thread — use for short commands only.
     */
    @UsedByGodot
    public String execCommandSync(String command) {
        try {
            ProcessBuilder pb = new ProcessBuilder("sh", "-c", command);
            pb.redirectErrorStream(true);

            String termuxPrefix = "/data/data/com.termux/files/usr/bin";
            File termuxBin = new File(termuxPrefix);
            if (termuxBin.exists()) {
                String path = termuxPrefix + ":" + System.getenv("PATH");
                pb.environment().put("PATH", path);
                pb.environment().put("HOME", "/data/data/com.termux/files/home");
                pb.environment().put("PREFIX", "/data/data/com.termux/files/usr");
            }

            Process process = pb.start();
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                output.append(line).append("\n");
            }
            process.waitFor();
            return output.toString().trim();
        } catch (Exception e) {
            return "Error: " + e.getMessage();
        }
    }

    // ── SMS ──────────────────────────────────────────────────────────

    @UsedByGodot
    public void sendSMS(String phone, String message) {
        Activity activity = getActivity();
        if (activity == null) {
            emitSignal("sms_failed", "No activity context");
            return;
        }

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.SEND_SMS)
                != PackageManager.PERMISSION_GRANTED) {
            // Request permission, then retry
            pendingSmsPhone = phone;
            pendingSmsMessage = message;
            ActivityCompat.requestPermissions(activity,
                    new String[]{Manifest.permission.SEND_SMS}, SMS_PERMISSION_CODE);
            return;
        }

        try {
            SmsManager smsManager;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                smsManager = activity.getSystemService(SmsManager.class);
            } else {
                smsManager = SmsManager.getDefault();
            }

            // Split long messages
            if (message.length() > 160) {
                java.util.ArrayList<String> parts = smsManager.divideMessage(message);
                smsManager.sendMultipartTextMessage(phone, null, parts, null, null);
            } else {
                smsManager.sendTextMessage(phone, null, message, null, null);
            }
            emitSignal("sms_sent", phone);
        } catch (Exception e) {
            emitSignal("sms_failed", e.getMessage());
        }
    }

    // ── Camera ───────────────────────────────────────────────────────

    @UsedByGodot
    public void openCamera() {
        Activity activity = getActivity();
        if (activity == null) return;

        // Try stock camera intent
        Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        if (intent.resolveActivity(activity.getPackageManager()) != null) {
            activity.startActivity(intent);
        }
    }

    // ── App management ───────────────────────────────────────────────

    @UsedByGodot
    public void openApp(String packageName) {
        Activity activity = getActivity();
        if (activity == null) return;

        Intent intent = activity.getPackageManager().getLaunchIntentForPackage(packageName);
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(intent);
        }
    }

    @UsedByGodot
    public String listApps() {
        Activity activity = getActivity();
        if (activity == null) return "[]";

        java.util.List<android.content.pm.ApplicationInfo> apps =
                activity.getPackageManager().getInstalledApplications(0);
        StringBuilder json = new StringBuilder("[");
        boolean first = true;
        for (android.content.pm.ApplicationInfo app : apps) {
            String name = activity.getPackageManager().getApplicationLabel(app).toString();
            String pkg = app.packageName;
            if (!first) json.append(",");
            json.append("{\"name\":\"").append(name.replace("\"", "'"))
                .append("\",\"package\":\"").append(pkg).append("\"}");
            first = false;
        }
        json.append("]");
        return json.toString();
    }

    @UsedByGodot
    public boolean isAppInstalled(String packageName) {
        Activity activity = getActivity();
        if (activity == null) return false;
        try {
            activity.getPackageManager().getPackageInfo(packageName, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    // ── URL ──────────────────────────────────────────────────────────

    @UsedByGodot
    public void openUrl(String url) {
        Activity activity = getActivity();
        if (activity == null) return;

        Intent intent = new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        activity.startActivity(intent);
    }

    // ── Utilities ────────────────────────────────────────────────────

    @UsedByGodot
    public void showToast(String message) {
        Activity activity = getActivity();
        if (activity == null) return;

        activity.runOnUiThread(() ->
                Toast.makeText(activity, message, Toast.LENGTH_SHORT).show()
        );
    }

    @UsedByGodot
    public void vibrate(int milliseconds) {
        Activity activity = getActivity();
        if (activity == null) return;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            VibratorManager vm = (VibratorManager) activity.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
            if (vm != null) {
                Vibrator vibrator = vm.getDefaultVibrator();
                vibrator.vibrate(VibrationEffect.createOneShot(milliseconds,
                        VibrationEffect.DEFAULT_AMPLITUDE));
            }
        } else {
            Vibrator vibrator = (Vibrator) activity.getSystemService(Context.VIBRATOR_SERVICE);
            if (vibrator != null) {
                vibrator.vibrate(milliseconds);
            }
        }
    }

    @UsedByGodot
    public boolean isTermuxInstalled() {
        return isAppInstalled("com.termux");
    }

    @UsedByGodot
    public String getPythonPath() {
        String termuxPython = "/data/data/com.termux/files/usr/bin/python3";
        File f = new File(termuxPython);
        if (f.exists()) {
            return termuxPython;
        }
        // Check bundled Python
        String filesDir = getActivity().getFilesDir().getAbsolutePath();
        String bundledPython = filesDir + "/python/bin/python3";
        File bf = new File(bundledPython);
        if (bf.exists()) {
            return bundledPython;
        }
        return "";
    }

    @UsedByGodot
    public String getFilesDir() {
        Activity activity = getActivity();
        if (activity == null) return "";
        return activity.getFilesDir().getAbsolutePath();
    }

    @UsedByGodot
    public String getExternalStorageDir() {
        File dir = android.os.Environment.getExternalStorageDirectory();
        return dir != null ? dir.getAbsolutePath() : "";
    }

    // ── Contacts ─────────────────────────────────────────────────────

    /**
     * Read contacts from the phone. Returns JSON array of {name, phone} objects.
     * @param query optional filter substring (empty = return all, max 50)
     */
    @UsedByGodot
    public String getContacts(String query) {
        Activity activity = getActivity();
        if (activity == null) return "[]";

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_CONTACTS)
                != PackageManager.PERMISSION_GRANTED) {
            return "Error: READ_CONTACTS permission not granted";
        }

        ContentResolver cr = activity.getContentResolver();
        String selection = null;
        String[] selectionArgs = null;
        if (query != null && !query.isEmpty()) {
            selection = ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " LIKE ?";
            selectionArgs = new String[]{"%" + query + "%"};
        }

        Cursor cursor = cr.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                new String[]{ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                        ContactsContract.CommonDataKinds.Phone.NUMBER},
                selection, selectionArgs,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC");

        StringBuilder json = new StringBuilder("[");
        if (cursor != null) {
            boolean first = true;
            int count = 0;
            while (cursor.moveToNext() && count < 50) {
                String name = cursor.getString(0);
                String phone = cursor.getString(1);
                if (name == null || phone == null) continue;
                if (!first) json.append(",");
                json.append("{\"name\":\"").append(name.replace("\"", "'"))
                    .append("\",\"phone\":\"").append(phone.replace("\"", "'"))
                    .append("\"}");
                first = false;
                count++;
            }
            cursor.close();
        }
        json.append("]");
        return json.toString();
    }

    // ── Location ─────────────────────────────────────────────────────

    /**
     * Get the last known location. Returns JSON {lat, lon, accuracy} or error string.
     * Emits "location_received" signal when a fresh location arrives.
     */
    @UsedByGodot
    public String getLocation() {
        Activity activity = getActivity();
        if (activity == null) return "{\"error\":\"no activity\"}";

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED
            && ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_COARSE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            return "Error: location permission not granted";
        }

        LocationManager lm = (LocationManager) activity.getSystemService(Context.LOCATION_SERVICE);

        // Try to get last known location from any provider
        Location best = null;
        for (String provider : lm.getProviders(true)) {
            Location loc = lm.getLastKnownLocation(provider);
            if (loc != null && (best == null || loc.getAccuracy() < best.getAccuracy())) {
                best = loc;
            }
        }

        if (best != null) {
            return "{\"lat\":" + best.getLatitude()
                + ",\"lon\":" + best.getLongitude()
                + ",\"accuracy\":" + best.getAccuracy()
                + ",\"provider\":\"" + best.getProvider() + "\"}";
        }

        // Request a single update
        try {
            lm.requestSingleUpdate(LocationManager.NETWORK_PROVIDER, new LocationListener() {
                @Override public void onLocationChanged(Location loc) {
                    emitSignal("location_received", loc.getLatitude(), loc.getLongitude(), loc.getAccuracy());
                }
                @Override public void onStatusChanged(String p, int s, Bundle b) {}
                @Override public void onProviderEnabled(String p) {}
                @Override public void onProviderDisabled(String p) {}
            }, Looper.getMainLooper());
        } catch (Exception e) {
            // ignore
        }

        return "{\"error\":\"no location available yet — requesting update\"}";
    }

    // ── Read SMS Inbox ───────────────────────────────────────────────

    /**
     * Read recent SMS messages from the inbox.
     * @param limit max messages to return (default 20)
     * @return JSON array of {sender, body, date} objects
     */
    @UsedByGodot
    public String readSmsInbox(int limit) {
        Activity activity = getActivity();
        if (activity == null) return "[]";

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_SMS)
                != PackageManager.PERMISSION_GRANTED) {
            return "Error: READ_SMS permission not granted";
        }

        if (limit <= 0 || limit > 100) limit = 20;

        ContentResolver cr = activity.getContentResolver();
        Cursor cursor = cr.query(
                android.net.Uri.parse("content://sms/inbox"),
                new String[]{"address", "body", "date"},
                null, null,
                "date DESC");

        StringBuilder json = new StringBuilder("[");
        if (cursor != null) {
            boolean first = true;
            int count = 0;
            while (cursor.moveToNext() && count < limit) {
                String sender = cursor.getString(0);
                String body = cursor.getString(1);
                long date = cursor.getLong(2);
                if (sender == null) sender = "unknown";
                if (body == null) body = "";
                if (!first) json.append(",");
                json.append("{\"sender\":\"").append(sender.replace("\"", "'"))
                    .append("\",\"body\":\"").append(body.replace("\"", "'").replace("\n", " "))
                    .append("\",\"date\":").append(date)
                    .append("}");
                first = false;
                count++;
            }
            cursor.close();
        }
        json.append("]");
        return json.toString();
    }

    // ── Alarms ───────────────────────────────────────────────────────

    /**
     * Set an alarm on the phone.
     * @param hour   hour of day (0-23)
     * @param minutes minute (0-59)
     * @param message label for the alarm (can be empty)
     */
    @UsedByGodot
    public void setAlarm(int hour, int minutes, String message) {
        Activity activity = getActivity();
        if (activity == null) return;

        Intent intent = new Intent(AlarmClock.ACTION_SET_ALARM)
                .putExtra(AlarmClock.EXTRA_HOUR, hour)
                .putExtra(AlarmClock.EXTRA_MINUTES, minutes)
                .putExtra(AlarmClock.EXTRA_MESSAGE, message != null ? message : "GhostKV Alarm")
                .putExtra(AlarmClock.EXTRA_SKIP_UI, false);
        if (intent.resolveActivity(activity.getPackageManager()) != null) {
            activity.startActivity(intent);
        }
    }

    /**
     * Start a timer on the phone.
     * @param seconds duration in seconds
     * @param message label for the timer
     */
    @UsedByGodot
    public void setTimer(int seconds, String message) {
        Activity activity = getActivity();
        if (activity == null) return;

        Intent intent = new Intent(AlarmClock.ACTION_SET_TIMER)
                .putExtra(AlarmClock.EXTRA_LENGTH, seconds)
                .putExtra(AlarmClock.EXTRA_MESSAGE, message != null ? message : "GhostKV Timer")
                .putExtra(AlarmClock.EXTRA_SKIP_UI, false);
        if (intent.resolveActivity(activity.getPackageManager()) != null) {
            activity.startActivity(intent);
        }
    }

    // ── Text-to-Speech ───────────────────────────────────────────────

    /**
     * Speak text aloud using Android TTS.
     */
    @UsedByGodot
    public void speak(String text) {
        Activity activity = getActivity();
        if (activity == null || text == null || text.isEmpty()) return;

        if (_tts == null) {
            _tts = new TextToSpeech(activity.getApplicationContext(), status -> {
                _ttsReady = (status == TextToSpeech.SUCCESS);
                if (_ttsReady && _tts != null) {
                    _tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ghostkv_tts");
                }
            });
        } else if (_ttsReady) {
            _tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ghostkv_tts");
        }
    }

    /**
     * Check if TTS is ready.
     */
    @UsedByGodot
    public boolean isTtsReady() {
        return _ttsReady;
    }

    // ── Speech-to-Text ───────────────────────────────────────────────

    /**
     * Launch the speech recognition intent.
     * Result is returned via the "speech_result" signal.
     * On failure, emits "speech_error".
     */
    @UsedByGodot
    public void startSpeechRecognition() {
        Activity activity = getActivity();
        if (activity == null) return;

        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to GhostKV");

        try {
            activity.startActivityForResult(intent, 2001);
        } catch (Exception e) {
            emitSignal("speech_error", "Speech recognition not available: " + e.getMessage());
        }
    }

    // ── Permission handling ──────────────────────────────────────────

    @UsedByGodot
    public boolean hasPermission(String permission) {
        Activity activity = getActivity();
        if (activity == null) return false;
        return ContextCompat.checkSelfPermission(activity, permission)
                == PackageManager.PERMISSION_GRANTED;
    }

    @UsedByGodot
    public void requestPermission(String permission) {
        Activity activity = getActivity();
        if (activity == null) return;
        ActivityCompat.requestPermissions(activity, new String[]{permission}, 1002);
    }
}
