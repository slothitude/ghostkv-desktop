package com.slothitude.ghostkv;

import android.Manifest;
import android.app.Activity;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.provider.MediaStore;
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
