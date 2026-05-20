package com.slothitude.ghostkv;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothDevice;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ContentProviderOperation;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.os.Environment;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.media.AudioManager;
import android.net.Uri;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.nfc.NfcAdapter;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.provider.AlarmClock;
import android.provider.CalendarContract;
import android.provider.CallLog;
import android.provider.ContactsContract;
import android.provider.MediaStore;
import android.provider.Settings;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.telephony.SmsManager;
import android.util.Log;
import android.view.WindowManager;
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
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * GhostKV Android Plugin — bridges Godot GDScript to Android system APIs.
 *
 * Exposes: execCommand, sendSMS, openCamera, openApp, openUrl, listApps,
 *          showToast, vibrate, isTermuxInstalled, getPythonPath
 */
public class GhostKVPlugin extends GodotPlugin implements GhostTelephony.TelephonyHost {

    private static final int SMS_PERMISSION_CODE = 1001;
    private static final int RECORD_AUDIO_REQUEST_CODE = 1003;
    private String pendingSmsPhone = "";
    private String pendingSmsMessage = "";
    private TextToSpeech _tts;
    private boolean _ttsReady = false;
    private boolean _flashlightOn = false;
    private SpeechRecognizer _speechRecognizer;
    private boolean _isListening = false;
    private Handler _mainHandler;
    private String _pendingTtsText = null;
    private String _pendingTtsId = null;
    private PowerManager.WakeLock _bgWakeLock = null;
    private final ExecutorService _cmdExecutor = Executors.newFixedThreadPool(4);
    private boolean _pendingListenerStart = false;
    private GhostTelephony _telephony;

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
        signals.add(new SignalInfo("listening_state", Boolean.class));
        signals.add(new SignalInfo("speech_partial", String.class));
        signals.add(new SignalInfo("tts_completed", String.class));
        signals.add(new SignalInfo("telegram_message", String.class));
        signals.add(new SignalInfo("on_incoming_call", String.class));
        signals.add(new SignalInfo("on_call_started", String.class));
        signals.add(new SignalInfo("on_call_ended", String.class));
        return signals;
    }

    // ── Shell execution ──────────────────────────────────────────────

    /**
     * Execute a shell command and return output.
     * Runs asynchronously — emits "command_completed" signal with (output, exitCode).
     */
    @UsedByGodot
    public void execCommand(String command) {
        _cmdExecutor.submit(() -> {
            Process process = null;
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

                process = pb.start();
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                StringBuilder output = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                }
                reader.close();
                int exitCode = process.waitFor();
                emitSignal("command_completed", output.toString().trim(), exitCode);
            } catch (Exception e) {
                emitSignal("command_completed", "Error: " + e.getMessage(), -1);
            } finally {
                if (process != null) process.destroy();
            }
        });
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

    private void _initTts() {
        Activity activity = getActivity();
        if (activity == null || _tts != null) return;
        _mainHandler = new Handler(Looper.getMainLooper());
        _tts = new TextToSpeech(activity.getApplicationContext(), status -> {
            _ttsReady = (status == TextToSpeech.SUCCESS);
            if (_ttsReady && _tts != null) {
                _tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                    @Override
                    public void onStart(String utteranceId) {}
                    @Override
                    public void onError(String utteranceId) {
                        emitSignal("tts_completed", utteranceId);
                    }
                    @Override
                    public void onDone(String utteranceId) {
                        emitSignal("tts_completed", utteranceId);
                    }
                });
                // Flush any pending speech that was queued before TTS was ready
                if (_pendingTtsText != null) {
                    _tts.speak(_pendingTtsText, TextToSpeech.QUEUE_FLUSH, null, _pendingTtsId != null ? _pendingTtsId : "ghostkv_tts");
                    _pendingTtsText = null;
                    _pendingTtsId = null;
                }
            }
        });
    }

    /**
     * Speak text aloud using Android TTS.
     */
    @UsedByGodot
    public void speak(String text) {
        if (text == null || text.isEmpty()) return;
        _initTts();
        if (_ttsReady) {
            _tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ghostkv_tts");
        } else {
            _pendingTtsText = text;
            _pendingTtsId = "ghostkv_tts";
        }
    }

    /**
     * Speak text with a specific utterance ID for completion tracking.
     */
    @UsedByGodot
    public void speakWithId(String text, String utteranceId) {
        if (text == null || text.isEmpty()) return;
        _initTts();
        if (_ttsReady) {
            _tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId);
        } else {
            // TTS not ready yet — queue for when init completes
            _pendingTtsText = text;
            _pendingTtsId = utteranceId;
        }
    }

    /**
     * Stop current TTS speech.
     */
    @UsedByGodot
    public void stopSpeaking() {
        if (_tts != null) {
            _tts.stop();
        }
    }

    /**
     * Check if TTS is currently speaking.
     */
    @UsedByGodot
    public boolean isSpeaking() {
        if (_tts == null) return false;
        return _tts.isSpeaking();
    }

    /**
     * Check if TTS is ready.
     */
    @UsedByGodot
    public boolean isTtsReady() {
        return _ttsReady;
    }

    // ── Speech-to-Text (in-app SpeechRecognizer) ─────────────────────

    /**
     * Start continuous in-app speech recognition.
     * Results via speech_result / speech_partial signals.
     * Listening state via listening_state signal.
     */
    @UsedByGodot
    public void startContinuousListening() {
        Activity activity = getActivity();
        if (activity == null) return;

        // Check RECORD_AUDIO permission
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            _pendingListenerStart = true;
            ActivityCompat.requestPermissions(activity, new String[]{Manifest.permission.RECORD_AUDIO}, RECORD_AUDIO_REQUEST_CODE);
            return;
        }

        // SpeechRecognizer MUST run on the main thread — post everything there
        if (_mainHandler == null) {
            _mainHandler = new Handler(Looper.getMainLooper());
        }
        _mainHandler.post(() -> _startListeningOnMainThread(activity));
    }

    private void _startListeningOnMainThread(Activity activity) {
        try {
            if (_speechRecognizer == null) {
                _speechRecognizer = SpeechRecognizer.createSpeechRecognizer(activity);
            }
            if (_speechRecognizer == null) {
                emitSignal("speech_error", "SpeechRecognizer not available on this device");
                return;
            }

            _speechRecognizer.setRecognitionListener(new RecognitionListener() {
                @Override public void onReadyForSpeech(Bundle params) {
                    Vibrator vib = (Vibrator) activity.getSystemService(Context.VIBRATOR_SERVICE);
                    if (vib != null) {
                        vib.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE));
                    }
                }
                @Override public void onBeginningOfSpeech() {}
                @Override public void onRmsChanged(float rmsdB) {}
                @Override public void onBufferReceived(byte[] buffer) {}
                @Override public void onEndOfSpeech() {
                    _isListening = false;
                    emitSignal("listening_state", false);
                }
                @Override public void onError(int error) {
                    _isListening = false;
                    emitSignal("listening_state", false);
                    if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                        emitSignal("speech_error", "NO_MATCH");
                    } else {
                        String msg;
                        switch (error) {
                            case SpeechRecognizer.ERROR_NETWORK_TIMEOUT: msg = "network_timeout"; break;
                            case SpeechRecognizer.ERROR_NETWORK: msg = "network_error"; break;
                            case SpeechRecognizer.ERROR_AUDIO: msg = "audio_error"; break;
                            case SpeechRecognizer.ERROR_CLIENT: msg = "client_error"; break;
                            case SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS: msg = "insufficient_permissions"; break;
                            case SpeechRecognizer.ERROR_RECOGNIZER_BUSY: msg = "recognizer_busy"; break;
                            case SpeechRecognizer.ERROR_SERVER: msg = "server_error"; break;
                            default: msg = "error_" + error; break;
                        }
                        emitSignal("speech_error", msg);
                    }
                }
                @Override public void onResults(Bundle results) {
                    _isListening = false;
                    emitSignal("listening_state", false);
                    java.util.ArrayList<String> matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                    if (matches != null && !matches.isEmpty()) {
                        emitSignal("speech_result", matches.get(0));
                    }
                }
                @Override public void onPartialResults(Bundle partialResults) {
                    java.util.ArrayList<String> partial = partialResults.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                    if (partial != null && !partial.isEmpty()) {
                        emitSignal("speech_partial", partial.get(0));
                    }
                }
                @Override public void onEvent(int eventType, Bundle params) {}
            });

            Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
            intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
            intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);

            _speechRecognizer.startListening(intent);
            _isListening = true;
            emitSignal("listening_state", true);
        } catch (Exception e) {
            emitSignal("speech_error", "Failed to start listening: " + e.getMessage());
        }
    }

    /**
     * Stop in-app speech recognition.
     */
    @UsedByGodot
    public void stopListening() {
        if (_speechRecognizer != null) {
            if (_mainHandler != null) {
                _mainHandler.post(() -> {
                    if (_speechRecognizer != null) {
                        _speechRecognizer.stopListening();
                        _speechRecognizer.destroy();
                        _speechRecognizer = null;
                    }
                });
            }
            _isListening = false;
            emitSignal("listening_state", false);
        }
    }

    /**
     * Check if currently listening for speech.
     */
    @UsedByGodot
    public boolean isListening() {
        return _isListening;
    }

    /**
     * Launch the speech recognition intent (legacy — use startContinuousListening instead).
     */
    @UsedByGodot
    public void startSpeechRecognition() {
        startContinuousListening();
    }

    // ── Telephony ──────────────────────────────────────────────────

    private void _initTelephony() {
        if (_telephony != null) return;
        Activity activity = getActivity();
        if (activity == null) return;
        _telephony = new GhostTelephony(this, activity.getApplicationContext());
    }

    @UsedByGodot
    public String makeCall(String number) {
        _initTelephony();
        if (_telephony != null) return _telephony.makeCall(number);
        // Fallback: open dialer without telephony delegate
        Activity activity = getActivity();
        if (activity == null) return "error:no_activity";
        Intent intent = new Intent(Intent.ACTION_DIAL, android.net.Uri.parse("tel:" + number));
        activity.startActivity(intent);
        return "ok:dialer_fallback";
    }

    @UsedByGodot
    public String answerCall() {
        _initTelephony();
        return _telephony != null ? _telephony.answerCall() : "error:no_telephony";
    }

    @UsedByGodot
    public String endCall() {
        _initTelephony();
        return _telephony != null ? _telephony.endCall() : "error:no_telephony";
    }

    @UsedByGodot
    public String startCallMonitor() {
        _initTelephony();
        return _telephony != null ? _telephony.startCallMonitor() : "error:no_telephony";
    }

    @UsedByGodot
    public String stopCallMonitor() {
        return _telephony != null ? _telephony.stopCallMonitor() : "error:no_telephony";
    }

    @UsedByGodot
    public String getCallState() {
        return _telephony != null ? _telephony.getCallState() : "idle";
    }

    @UsedByGodot
    public String setMicMute(boolean mute) {
        return _telephony != null ? _telephony.setMicMute(mute) : "error:no_telephony";
    }

    @UsedByGodot
    public String setSpeakerphone(boolean on) {
        return _telephony != null ? _telephony.setSpeakerphone(on) : "error:no_telephony";
    }

    @UsedByGodot
    public boolean isDefaultDialer() {
        return _telephony != null && _telephony.isDefaultDialer();
    }

    @UsedByGodot
    public void requestDefaultDialer() {
        if (_telephony != null) _telephony.requestDefaultDialer();
    }

    // ── TelephonyHost interface implementation ─────────────────────────

    @Override
    public void emitTelephonySignal(String signalName, String arg) {
        emitSignal(signalName, arg);
    }

    @Override
    public Activity getHostActivity() {
        return getActivity();
    }

    // ── WhatsApp ────────────────────────────────────────────────────

    @UsedByGodot
    public boolean sendWhatsApp(String phone, String message) {
        Activity activity = getActivity();
        if (activity == null) return false;

        // Try ACTION_SENDTO with smsto: URI first (pre-fills message, opens specific chat)
        Intent intent = new Intent(Intent.ACTION_SENDTO,
                Uri.parse("smsto:" + phone));
        intent.setPackage("com.whatsapp");
        intent.putExtra("sms_body", message);

        if (intent.resolveActivity(activity.getPackageManager()) != null) {
            activity.startActivity(intent);
            return true;
        }

        // Fallback: ACTION_SEND with text (no phone targeting, but opens WhatsApp)
        Intent fallback = new Intent(Intent.ACTION_SEND);
        fallback.setType("text/plain");
        fallback.putExtra(Intent.EXTRA_TEXT, message);
        fallback.setPackage("com.whatsapp");
        if (fallback.resolveActivity(activity.getPackageManager()) != null) {
            activity.startActivity(fallback);
            return true;
        }

        // WhatsApp not installed
        return false;
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

    // ── Media control ─────────────────────────────────────────────

    @UsedByGodot
    public void mediaControl(String action) {
        Activity activity = getActivity();
        if (activity == null) return;
        Intent intent = new Intent(action);
        // Simulate media button key event for reliable control
        switch (action) {
            case "play":
                intent.setAction("com.android.intent.action.MEDIA_BUTTON");
                intent.putExtra(Intent.EXTRA_KEY_EVENT, new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PLAY));
                activity.sendOrderedBroadcast(intent, null);
                break;
            case "pause":
                intent.setAction("com.android.intent.action.MEDIA_BUTTON");
                intent.putExtra(Intent.EXTRA_KEY_EVENT, new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PAUSE));
                activity.sendOrderedBroadcast(intent, null);
                break;
            case "next":
                intent.setAction("com.android.intent.action.MEDIA_BUTTON");
                intent.putExtra(Intent.EXTRA_KEY_EVENT, new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_NEXT));
                activity.sendOrderedBroadcast(intent, null);
                break;
            case "previous":
                intent.setAction("com.android.intent.action.MEDIA_BUTTON");
                intent.putExtra(Intent.EXTRA_KEY_EVENT, new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS));
                activity.sendOrderedBroadcast(intent, null);
                break;
        }
    }

    // ── Volume control ────────────────────────────────────────────

    @UsedByGodot
    public int getVolume(String streamType) {
        Activity activity = getActivity();
        if (activity == null) return -1;
        AudioManager am = (AudioManager) activity.getSystemService(Context.AUDIO_SERVICE);
        int stream = _streamTypeToInt(streamType);
        return am.getStreamVolume(stream);
    }

    @UsedByGodot
    public int getMaxVolume(String streamType) {
        Activity activity = getActivity();
        if (activity == null) return -1;
        AudioManager am = (AudioManager) activity.getSystemService(Context.AUDIO_SERVICE);
        int stream = _streamTypeToInt(streamType);
        return am.getStreamMaxVolume(stream);
    }

    @UsedByGodot
    public void setVolume(String streamType, int volume) {
        Activity activity = getActivity();
        if (activity == null) return;
        AudioManager am = (AudioManager) activity.getSystemService(Context.AUDIO_SERVICE);
        int stream = _streamTypeToInt(streamType);
        int max = am.getStreamMaxVolume(stream);
        if (volume < 0) volume = 0;
        if (volume > max) volume = max;
        am.setStreamVolume(stream, volume, 0);
    }

    private int _streamTypeToInt(String streamType) {
        switch (streamType.toLowerCase()) {
            case "ring": return AudioManager.STREAM_RING;
            case "alarm": return AudioManager.STREAM_ALARM;
            case "notification": return AudioManager.STREAM_NOTIFICATION;
            case "system": return AudioManager.STREAM_SYSTEM;
            case "voice_call": return AudioManager.STREAM_VOICE_CALL;
            default: return AudioManager.STREAM_MUSIC;
        }
    }

    // ── Brightness control ────────────────────────────────────────

    @UsedByGodot
    public float getBrightness() {
        Activity activity = getActivity();
        if (activity == null) return -1;
        try {
            return Settings.System.getFloat(activity.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS);
        } catch (Settings.SettingNotFoundException e) {
            return -1;
        }
    }

    @UsedByGodot
    public void setBrightness(int brightness) {
        Activity activity = getActivity();
        if (activity == null) return;
        if (brightness < 0) brightness = 0;
        if (brightness > 255) brightness = 255;
        // Enable manual brightness mode
        Settings.System.putInt(activity.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL);
        Settings.System.putInt(activity.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS, brightness);
    }

    // ── Battery status ────────────────────────────────────────────

    @UsedByGodot
    public String getBatteryStatus() {
        Activity activity = getActivity();
        if (activity == null) return "{}";
        android.content.IntentFilter filter = new android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED);
        android.content.Intent batteryIntent = activity.registerReceiver(null, filter);
        if (batteryIntent == null) return "{}";

        int level = batteryIntent.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1);
        int scale = batteryIntent.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1);
        int status = batteryIntent.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1);
        int plugged = batteryIntent.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, -1);
        int health = batteryIntent.getIntExtra(android.os.BatteryManager.EXTRA_HEALTH, -1);
        float pct = (scale > 0) ? (level * 100.0f / scale) : 0;

        String statusStr;
        switch (status) {
            case android.os.BatteryManager.BATTERY_STATUS_CHARGING: statusStr = "charging"; break;
            case android.os.BatteryManager.BATTERY_STATUS_DISCHARGING: statusStr = "discharging"; break;
            case android.os.BatteryManager.BATTERY_STATUS_FULL: statusStr = "full"; break;
            case android.os.BatteryManager.BATTERY_STATUS_NOT_CHARGING: statusStr = "not_charging"; break;
            default: statusStr = "unknown";
        }

        String pluggedStr;
        switch (plugged) {
            case android.os.BatteryManager.BATTERY_PLUGGED_AC: pluggedStr = "ac"; break;
            case android.os.BatteryManager.BATTERY_PLUGGED_USB: pluggedStr = "usb"; break;
            case android.os.BatteryManager.BATTERY_PLUGGED_WIRELESS: pluggedStr = "wireless"; break;
            default: pluggedStr = "none";
        }

        String healthStr;
        switch (health) {
            case android.os.BatteryManager.BATTERY_HEALTH_GOOD: healthStr = "good"; break;
            case android.os.BatteryManager.BATTERY_HEALTH_OVERHEAT: healthStr = "overheat"; break;
            case android.os.BatteryManager.BATTERY_HEALTH_DEAD: healthStr = "dead"; break;
            case android.os.BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE: healthStr = "over_voltage"; break;
            default: healthStr = "unknown";
        }

        return "{\"level\":" + Math.round(pct) + ",\"status\":\"" + statusStr
            + "\",\"plugged\":\"" + pluggedStr + "\",\"health\":\"" + healthStr + "\"}";
    }

    // ── WiFi info ─────────────────────────────────────────────────

    @UsedByGodot
    public String getWifiInfo() {
        Activity activity = getActivity();
        if (activity == null) return "{}";
        WifiManager wm = (WifiManager) activity.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wm == null || !wm.isWifiEnabled()) return "{\"enabled\":false}";

        WifiInfo info = wm.getConnectionInfo();
        String ssid = info.getSSID();
        // Remove quotes from SSID
        if (ssid != null && ssid.startsWith("\"") && ssid.endsWith("\"")) {
            ssid = ssid.substring(1, ssid.length() - 1);
        }
        // Android 8.1+ returns <unknown ssid> without location permission
        if (ssid == null || ssid.equals("<unknown ssid>")) {
            boolean hasLocation = ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
            ssid = hasLocation ? "unknown" : "unknown (enable location permission)";
        }
        int ip = info.getIpAddress();
        String ipStr = (ip == 0) ? "0.0.0.0" :
            String.format("%d.%d.%d.%d", ip & 0xff, (ip >> 8) & 0xff, (ip >> 16) & 0xff, (ip >> 24) & 0xff);
        int rssi = info.getRssi();
        int level = android.net.wifi.WifiManager.calculateSignalLevel(rssi, 5);

        return "{\"enabled\":true,\"ssid\":\"" + ssid.replace("\"", "'")
            + "\",\"ip\":\"" + ipStr
            + "\",\"rssi\":" + rssi
            + ",\"signal_level\":" + level + "}";
    }

    // ── Screen control ────────────────────────────────────────────

    @UsedByGodot
    public void wakeScreen() {
        Activity activity = getActivity();
        if (activity == null) return;
        PowerManager pm = (PowerManager) activity.getSystemService(Context.POWER_SERVICE);
        PowerManager.WakeLock wl = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK | PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "GhostKV::WakeScreen");
        wl.acquire(3000); // 3 seconds
        wl.release();
    }

    @UsedByGodot
    public void setScreenTimeout(int seconds) {
        Activity activity = getActivity();
        if (activity == null) return;
        Settings.System.putInt(activity.getContentResolver(), Settings.System.SCREEN_OFF_TIMEOUT, seconds * 1000);
    }

    @UsedByGodot
    public int getScreenTimeout() {
        Activity activity = getActivity();
        if (activity == null) return -1;
        try {
            return Settings.System.getInt(activity.getContentResolver(), Settings.System.SCREEN_OFF_TIMEOUT) / 1000;
        } catch (Settings.SettingNotFoundException e) {
            return -1;
        }
    }

    // ── Share intent ──────────────────────────────────────────────

    @UsedByGodot
    public void shareText(String text) {
        Activity activity = getActivity();
        if (activity == null) return;
        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setType("text/plain");
        intent.putExtra(Intent.EXTRA_TEXT, text);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        activity.startActivity(Intent.createChooser(intent, "Share via"));
    }

    // ── File write ────────────────────────────────────────────────

    @UsedByGodot
    public String writeFile(String filename, String content) {
        Activity activity = getActivity();
        if (activity == null) return "Error: no activity";
        try {
            // Save to Downloads directory
            java.io.File dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            java.io.File file = new java.io.File(dir, filename);
            java.io.FileWriter writer = new java.io.FileWriter(file);
            writer.write(content);
            writer.close();
            // Make visible via MediaStore (MediaScannerConnection replaces deprecated broadcast)
            android.media.MediaScannerConnection.scanFile(activity, new String[]{file.getAbsolutePath()}, null, null);
            return "Saved to Downloads/" + filename;
        } catch (Exception e) {
            return "Error: " + e.getMessage();
        }
    }

    // ── List directory ────────────────────────────────────────────

    @UsedByGodot
    public String listDirectory(String path) {
        try {
            java.io.File dir;
            if (path.isEmpty() || path.equals("/")) {
                dir = Environment.getExternalStorageDirectory();
            } else if (path.equals("downloads")) {
                dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            } else if (path.equals("dcim") || path.equals("photos")) {
                dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM);
            } else if (path.equals("documents")) {
                dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS);
            } else {
                dir = new java.io.File(path);
            }
            if (!dir.exists() || !dir.isDirectory()) {
                return "Error: directory not found: " + path;
            }
            java.io.File[] files = dir.listFiles();
            if (files == null) return "Error: cannot read directory";
            StringBuilder sb = new StringBuilder("[");
            for (int i = 0; i < files.length && i < 100; i++) {
                if (i > 0) sb.append(",");
                java.io.File f = files[i];
                sb.append("{\"name\":\"").append(f.getName().replace("\"", "'"))
                  .append("\",\"is_dir\":").append(f.isDirectory())
                  .append(",\"size\":").append(f.length());
                long modified = f.lastModified();
                sb.append(",\"modified\":").append(modified).append("}");
            }
            sb.append("]");
            return sb.toString();
        } catch (Exception e) {
            return "Error: " + e.getMessage();
        }
    }

    // ── Contact management ────────────────────────────────────────

    @UsedByGodot
    public String addContact(String name, String phone) {
        Activity activity = getActivity();
        if (activity == null) return "Error: no activity";

        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_CONTACTS)
                != PackageManager.PERMISSION_GRANTED) {
            return "Error: WRITE_CONTACTS permission not granted";
        }

        try {
            ArrayList<ContentProviderOperation> ops = new ArrayList<>();
            ops.add(ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, (String) null)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, (String) null)
                .build());
            ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, name)
                .build());
            ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, phone)
                .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE)
                .build());
            activity.getContentResolver().applyBatch(ContactsContract.AUTHORITY, ops);
            return "Contact added: " + name + " (" + phone + ")";
        } catch (Exception e) {
            return "Error: " + e.getMessage();
        }
    }

    // ── Bluetooth ─────────────────────────────────────────────────

    @UsedByGodot
    public String getBluetoothDevices() {
        Activity activity = getActivity();
        if (activity == null) return "[]";
        BluetoothManager bm = (BluetoothManager) activity.getSystemService(Context.BLUETOOTH_SERVICE);
        if (bm == null) return "[]";
        BluetoothAdapter adapter = bm.getAdapter();
        if (adapter == null || !adapter.isEnabled()) return "{\"enabled\":false}";

        Set<BluetoothDevice> paired = adapter.getBondedDevices();
        StringBuilder sb = new StringBuilder("{\"enabled\":true,\"devices\":[");
        int i = 0;
        for (BluetoothDevice device : paired) {
            if (i > 0) sb.append(",");
            sb.append("{\"name\":\"").append(device.getName().replace("\"", "'"))
              .append("\",\"address\":\"").append(device.getAddress())
              .append("\",\"type\":").append(device.getType())
              .append("}");
            i++;
        }
        sb.append("],\"count\":").append(i).append("}");
        return sb.toString();
    }

    // ── NFC ───────────────────────────────────────────────────────

    @UsedByGodot
    public String getNfcStatus() {
        Activity activity = getActivity();
        if (activity == null) return "{}";
        NfcAdapter nfc = NfcAdapter.getDefaultAdapter(activity);
        if (nfc == null) return "{\"available\":false}";
        return "{\"available\":true,\"enabled\":" + nfc.isEnabled() + "}";
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

    @Override
    public void onMainRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode == RECORD_AUDIO_REQUEST_CODE) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                if (_pendingListenerStart) {
                    _pendingListenerStart = false;
                    startContinuousListening();
                }
            } else {
                emitSignal("speech_error", "RECORD_AUDIO permission denied");
            }
        }
        // Forward telephony permissions
        if (_telephony != null) {
            _telephony.onPermissionResult(requestCode, permissions, grantResults);
        }
    }

    // ── Telegram bot background polling ─────────────────────────────────

    private Thread _tgPollThread = null;
    private volatile boolean _tgPollRunning = false;
    private String _tgBotToken = "";
    private String _tgChatId = "";
    private int _tgUpdateOffset = 0;

    @UsedByGodot
    public void startTelegramPolling(String botToken, String chatId) {
        stopTelegramPolling();
        _tgBotToken = botToken;
        _tgChatId = chatId;
        _tgUpdateOffset = 0;
        _tgPollRunning = true;

        // Acquire wake lock so CPU stays on (capped at 10 min as safety net)
        Activity activity = getActivity();
        if (activity != null) {
            PowerManager pm = (PowerManager) activity.getSystemService(Context.POWER_SERVICE);
            if (pm != null && (_bgWakeLock == null || !_bgWakeLock.isHeld())) {
                _bgWakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GhostKV::TgPoll");
                _bgWakeLock.acquire(10 * 60 * 1000L);
            }
        }

        _tgPollThread = new Thread(this::_tgPollLoop, "TgPoll");
        _tgPollThread.setDaemon(true);
        _tgPollThread.start();
        Log.i("GhostKV", "Telegram polling started in background thread");
    }

    @UsedByGodot
    public void stopTelegramPolling() {
        _tgPollRunning = false;
        if (_tgPollThread != null) {
            _tgPollThread.interrupt();
            _tgPollThread = null;
        }
        if (_bgWakeLock != null && _bgWakeLock.isHeld()) {
            _bgWakeLock.release();
            _bgWakeLock = null;
        }
    }

    @UsedByGodot
    public boolean isTelegramPolling() {
        return _tgPollThread != null && _tgPollThread.isAlive();
    }

    @UsedByGodot
    public void tgSend(String botToken, String chatId, String text) {
        _cmdExecutor.submit(() -> {
            HttpURLConnection conn = null;
            try {
                URL url = new URL("https://api.telegram.org/bot" + botToken + "/sendMessage");
                conn = (HttpURLConnection) url.openConnection();
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setConnectTimeout(10000);
                conn.setReadTimeout(10000);
                conn.setDoOutput(true);
                String body = "{\"chat_id\":\"" + chatId + "\",\"text\":" + _jsonStr(text) + "}";
                OutputStream os = conn.getOutputStream();
                os.write(body.getBytes("UTF-8"));
                os.close();
                conn.getInputStream().close();
            } catch (Exception e) {
                Log.w("GhostKV", "tgSend failed: " + e.getMessage());
            } finally {
                if (conn != null) conn.disconnect();
            }
        });
    }

    private void _tgPollLoop() {
        try {
            while (_tgPollRunning) {
                try {
                    URL url = new URL("https://api.telegram.org/bot" + _tgBotToken + "/getUpdates");
                    HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                    conn.setRequestMethod("POST");
                    conn.setRequestProperty("Content-Type", "application/json");
                    conn.setConnectTimeout(15000);
                    conn.setReadTimeout(15000);
                    conn.setDoOutput(true);
                    String body = "{\"offset\":" + _tgUpdateOffset + ",\"timeout\":10,\"allowed_updates\":[\"message\"]}";
                    OutputStream os = conn.getOutputStream();
                    os.write(body.getBytes("UTF-8"));
                    os.close();

                    BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
                    StringBuilder sb = new StringBuilder();
                    String line;
                    while ((line = reader.readLine()) != null) sb.append(line);
                    reader.close();
                    conn.disconnect();

                    JSONObject json = new JSONObject(sb.toString());
                    if (!json.getBoolean("ok")) {
                        Thread.sleep(3000);
                        continue;
                    }

                    JSONArray updates = json.getJSONArray("result");
                    for (int i = 0; i < updates.length(); i++) {
                        JSONObject update = updates.getJSONObject(i);
                        _tgUpdateOffset = update.getInt("update_id") + 1;

                        if (!update.has("message")) continue;
                        JSONObject msg = update.getJSONObject("message");

                        String msgChatId = String.valueOf(msg.getJSONObject("chat").getLong("id"));
                        if (!msgChatId.equals(_tgChatId)) continue;

                        String text = msg.optString("text", "");
                        if (text.isEmpty()) continue;

                        Log.i("GhostKV", "Telegram message: " + text);

                        // Bring app to foreground so Godot's main loop resumes
                        _bringToFront();

                        // Emit signal on render thread
                        final String msgText = text;
                        getActivity().runOnUiThread(() -> {
                            emitSignal("telegram_message", msgText);
                        });
                    }
                } catch (InterruptedException e) {
                    break;
                } catch (Exception e) {
                    Log.w("GhostKV", "TgPoll error: " + e.getMessage());
                    try { Thread.sleep(3000); } catch (InterruptedException ie) { break; }
                }
            }
        } finally {
            if (_bgWakeLock != null && _bgWakeLock.isHeld()) {
                try { _bgWakeLock.release(); } catch (RuntimeException ignored) {}
            }
            Log.i("GhostKV", "Telegram polling stopped");
        }
    }

    private void _bringToFront() {
        Activity activity = getActivity();
        if (activity == null) return;
        Intent intent = new Intent(activity, activity.getClass());
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        activity.getApplicationContext().startActivity(intent);
    }

    private String _jsonStr(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"")
            .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + "\"";
    }

    @Override
    public void onMainDestroy() {
        _cmdExecutor.shutdownNow();
        stopTelegramPolling();
        if (_telephony != null) {
            _telephony.onDestroy();
            _telephony = null;
        }
        if (_speechRecognizer != null) {
            _speechRecognizer.destroy();
            _speechRecognizer = null;
        }
        if (_tts != null) {
            _tts.stop();
            _tts.shutdown();
            _tts = null;
        }
    }
}
