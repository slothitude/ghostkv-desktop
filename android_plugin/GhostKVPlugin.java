package com.slothitude.ghostkv;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
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
import android.provider.CalendarContract;
import android.provider.CallLog;
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
    private boolean _flashlightOn = false;

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

            // Always use divideMessage — it handles both GSM-7 (160 char)
            // and UCS-2 (70 char for emoji/unicode) encoding limits correctly
            java.util.ArrayList<String> parts = smsManager.divideMessage(message);
            if (parts.size() > 1) {
                smsManager.sendMultipartTextMessage(phone, null, parts, null, null);
            } else {
                smsManager.sendTextMessage(phone, null, parts.get(0), null, null);
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

    // ── Phone Calls ──────────────────────────────────────────────────

    @UsedByGodot
    public void makeCall(String phone) {
        Activity activity = getActivity();
        if (activity == null) return;

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CALL_PHONE)
                == PackageManager.PERMISSION_GRANTED) {
            Intent intent = new Intent(Intent.ACTION_CALL, android.net.Uri.parse("tel:" + phone));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(intent);
        } else {
            // Fallback: open dialer
            Intent intent = new Intent(Intent.ACTION_DIAL, android.net.Uri.parse("tel:" + phone));
            activity.startActivity(intent);
        }
    }

    // ── Call Log ─────────────────────────────────────────────────────

    @UsedByGodot
    public String getCallLog(int limit) {
        Activity activity = getActivity();
        if (activity == null) return "[]";

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_CALL_LOG)
                != PackageManager.PERMISSION_GRANTED) {
            return "Error: READ_CALL_LOG permission not granted";
        }

        if (limit <= 0 || limit > 100) limit = 20;

        ContentResolver cr = activity.getContentResolver();
        Cursor cursor = cr.query(
                CallLog.Calls.CONTENT_URI,
                new String[]{CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME,
                        CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE},
                null, null, CallLog.Calls.DATE + " DESC");

        StringBuilder json = new StringBuilder("[");
        if (cursor != null) {
            boolean first = true;
            int count = 0;
            while (cursor.moveToNext() && count < limit) {
                String number = cursor.getString(0);
                String name = cursor.getString(1);
                long date = cursor.getLong(2);
                String duration = cursor.getString(3);
                int type = cursor.getInt(4);

                String typeStr;
                switch (type) {
                    case CallLog.Calls.INCOMING_TYPE: typeStr = "incoming"; break;
                    case CallLog.Calls.OUTGOING_TYPE: typeStr = "outgoing"; break;
                    case CallLog.Calls.MISSED_TYPE: typeStr = "missed"; break;
                    case CallLog.Calls.REJECTED_TYPE: typeStr = "rejected"; break;
                    case CallLog.Calls.BLOCKED_TYPE: typeStr = "blocked"; break;
                    default: typeStr = "unknown";
                }

                if (!first) json.append(",");
                json.append("{\"number\":\"").append(number != null ? number : "unknown")
                    .append("\",\"name\":\"").append(name != null ? name.replace("\"", "'") : "")
                    .append("\",\"date\":").append(date)
                    .append(",\"duration\":").append(duration != null ? duration : "0")
                    .append(",\"type\":\"").append(typeStr)
                    .append("\"}");
                first = false;
                count++;
            }
            cursor.close();
        }
        json.append("]");
        return json.toString();
    }

    // ── Calendar ─────────────────────────────────────────────────────

    @UsedByGodot
    public String getCalendarEvents(int limit) {
        Activity activity = getActivity();
        if (activity == null) return "[]";

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_CALENDAR)
                != PackageManager.PERMISSION_GRANTED) {
            return "Error: READ_CALENDAR permission not granted";
        }

        if (limit <= 0 || limit > 100) limit = 20;

        ContentResolver cr = activity.getContentResolver();
        Cursor cursor = cr.query(
                CalendarContract.Events.CONTENT_URI,
                new String[]{CalendarContract.Events.TITLE, CalendarContract.Events.DTSTART,
                        CalendarContract.Events.DTEND, CalendarContract.Events.EVENT_LOCATION,
                        CalendarContract.Events.DESCRIPTION},
                null, null, CalendarContract.Events.DTSTART + " DESC");

        StringBuilder json = new StringBuilder("[");
        if (cursor != null) {
            boolean first = true;
            int count = 0;
            while (cursor.moveToNext() && count < limit) {
                String title = cursor.getString(0);
                long dtStart = cursor.getLong(1);
                long dtEnd = cursor.getLong(2);
                String location = cursor.getString(3);
                String description = cursor.getString(4);

                if (!first) json.append(",");
                json.append("{\"title\":\"").append(title != null ? title.replace("\"", "'") : "")
                    .append("\",\"start\":").append(dtStart)
                    .append(",\"end\":").append(dtEnd)
                    .append(",\"location\":\"").append(location != null ? location.replace("\"", "'") : "")
                    .append("\",\"description\":\"").append(description != null ? description.replace("\"", "'").replace("\n", " ") : "")
                    .append("\"}");
                first = false;
                count++;
            }
            cursor.close();
        }
        json.append("]");
        return json.toString();
    }

    @UsedByGodot
    public String createCalendarEvent(String title, String description, long startMs, long endMs) {
        Activity activity = getActivity();
        if (activity == null) return "Error: no activity";

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_CALENDAR)
                != PackageManager.PERMISSION_GRANTED) {
            return "Error: WRITE_CALENDAR permission not granted";
        }

        ContentResolver cr = activity.getContentResolver();
        ContentValues values = new ContentValues();
        values.put(CalendarContract.Events.DTSTART, startMs);
        values.put(CalendarContract.Events.DTEND, endMs);
        values.put(CalendarContract.Events.TITLE, title);
        values.put(CalendarContract.Events.DESCRIPTION, description != null ? description : "");
        values.put(CalendarContract.Events.CALENDAR_ID, _getDefaultCalendarId(cr));
        values.put(CalendarContract.Events.EVENT_TIMEZONE, java.util.TimeZone.getDefault().getID());

        android.net.Uri uri = cr.insert(CalendarContract.Events.CONTENT_URI, values);
        if (uri != null) {
            return "Event created: " + title;
        }
        return "Error: failed to create event";
    }

    private long _getDefaultCalendarId(ContentResolver cr) {
        String[] projection = new String[]{CalendarContract.Calendars._ID};
        Cursor cursor = cr.query(CalendarContract.Calendars.CONTENT_URI, projection, null, null, null);
        if (cursor != null) {
            if (cursor.moveToFirst()) {
                long id = cursor.getLong(0);
                cursor.close();
                return id;
            }
            cursor.close();
        }
        return 1;
    }

    // ── Clipboard ────────────────────────────────────────────────────

    @UsedByGodot
    public String readClipboard() {
        Activity activity = getActivity();
        if (activity == null) return "";

        ClipboardManager cm = (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm != null && cm.hasPrimaryClip()) {
            ClipData.Item item = cm.getPrimaryClip().getItemAt(0);
            if (item != null && item.getText() != null) {
                return item.getText().toString();
            }
        }
        return "";
    }

    @UsedByGodot
    public void writeClipboard(String text) {
        Activity activity = getActivity();
        if (activity == null) return;

        ClipboardManager cm = (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm != null) {
            ClipData clip = ClipData.newPlainText("text", text);
            cm.setPrimaryClip(clip);
        }
    }

    // ── Flashlight ───────────────────────────────────────────────────

    @UsedByGodot
    public void setFlashlight(boolean on) {
        Activity activity = getActivity();
        if (activity == null) return;

        CameraManager cameraManager = (CameraManager) activity.getSystemService(Context.CAMERA_SERVICE);
        if (cameraManager == null) return;

        try {
            for (String cameraId : cameraManager.getCameraIdList()) {
                CameraCharacteristics chars = cameraManager.getCameraCharacteristics(cameraId);
                Boolean hasFlash = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                Integer facing = chars.get(CameraCharacteristics.LENS_FACING);
                if (hasFlash != null && hasFlash && facing != null
                        && facing == CameraCharacteristics.LENS_FACING_BACK) {
                    cameraManager.setTorchMode(cameraId, on);
                    _flashlightOn = on;
                    return;
                }
            }
        } catch (Exception e) {
            // ignore
        }
    }

    @UsedByGodot
    public boolean isFlashlightOn() {
        return _flashlightOn;
    }

    // ── Notifications ────────────────────────────────────────────────

    @UsedByGodot
    public String getNotifications() {
        if (!GhostKVNotificationListener.isConnected()) {
            return "Error: notification access not granted. Open Settings > Apps > GhostKV > Notification access";
        }
        return GhostKVNotificationListener.getCachedNotificationsJson();
    }

    @UsedByGodot
    public void openNotificationSettings() {
        Activity activity = getActivity();
        if (activity == null) return;
        Intent intent = new Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS");
        activity.startActivity(intent);
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
