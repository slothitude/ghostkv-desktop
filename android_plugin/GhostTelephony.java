package com.slothitude.ghostkv;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.telecom.TelecomManager;
import android.telephony.PhoneStateListener;
import android.telephony.TelephonyManager;
import android.util.Log;

import androidx.core.content.ContextCompat;

/**
 * GhostTelephony — Telephony bridge for GhostKV Android plugin.
 *
 * Delegate class that slots into GhostKVPlugin. Uses callback interface
 * for signal emission and activity access since GodotPlugin methods are protected.
 *
 * Signals emitted via TelephonyCallback interface:
 *   onIncomingCall(String number)
 *   onCallStarted(String number)
 *   onCallEnded(String duration_seconds)
 *   onPermissionDenied(String permission)
 *
 * Required permissions in AAR AndroidManifest.xml:
 *   CALL_PHONE, READ_PHONE_STATE, ANSWER_PHONE_CALLS, READ_CALL_LOG, PROCESS_OUTGOING_CALLS
 */
public class GhostTelephony {

    private static final String TAG = "GhostTelephony";

    public static final int RC_CALL_PHONE   = 3001;
    public static final int RC_PHONE_STATE  = 3002;
    public static final int RC_ANSWER_CALLS = 3003;

    // Callback interface — GhostKVPlugin implements this to emit Godot signals
    public interface TelephonyHost {
        void emitTelephonySignal(String signalName, String arg);
        Activity getHostActivity();
    }

    private final TelephonyHost _host;
    private final Context       _ctx;

    private TelephonyManager   _telephonyManager;
    private TelecomManager     _telecomManager;
    private AudioManager       _audioManager;

    private PhoneStateListener _phoneStateListener;

    private boolean _monitoring   = false;
    private String  _activeNumber = "";
    private long    _callStartMs  = 0;

    private boolean _pendingCall   = false;
    private String  _pendingNumber = "";
    private boolean _pendingAnswer = false;

    public GhostTelephony(TelephonyHost host, Context ctx) {
        _host = host;
        _ctx  = ctx;
        _telephonyManager = (TelephonyManager) ctx.getSystemService(Context.TELEPHONY_SERVICE);
        _telecomManager   = (TelecomManager)   ctx.getSystemService(Context.TELECOM_SERVICE);
        _audioManager     = (AudioManager)      ctx.getSystemService(Context.AUDIO_SERVICE);
        _wireInCallServiceBridge();
    }

    // ════════════════════════════════════════════════════════════════════════
    // PUBLIC API — called via GhostKVPlugin @UsedByGodot delegates
    // ════════════════════════════════════════════════════════════════════════

    public String makeCall(String number) {
        if (!hasPermission(Manifest.permission.CALL_PHONE)) {
            _pendingCall   = true;
            _pendingNumber = number;
            requestPermission(Manifest.permission.CALL_PHONE, RC_CALL_PHONE);
            return "requesting_permission:CALL_PHONE";
        }
        return _placeCall(number);
    }

    public String answerCall() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return "error:api_level:requires_android_8";
        }
        if (!hasPermission(Manifest.permission.ANSWER_PHONE_CALLS)) {
            _pendingAnswer = true;
            requestPermission(Manifest.permission.ANSWER_PHONE_CALLS, RC_ANSWER_CALLS);
            return "requesting_permission:ANSWER_PHONE_CALLS";
        }
        return _acceptRingingCall();
    }

    public String endCall() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (!hasPermission(Manifest.permission.ANSWER_PHONE_CALLS)) {
                return "error:permission_denied:ANSWER_PHONE_CALLS";
            }
            try {
                _telecomManager.endCall();
                return "ok";
            } catch (Exception e) {
                Log.e(TAG, "endCall failed", e);
                return "error:" + e.getMessage();
            }
        }
        return "error:api_level:requires_android_9";
    }

    public String startCallMonitor() {
        if (_monitoring) return "ok:already_monitoring";
        if (!hasPermission(Manifest.permission.READ_PHONE_STATE)) {
            requestPermission(Manifest.permission.READ_PHONE_STATE, RC_PHONE_STATE);
            return "requesting_permission:READ_PHONE_STATE";
        }
        _registerPhoneStateListener();
        _monitoring = true;
        return "ok";
    }

    public String stopCallMonitor() {
        if (!_monitoring) return "ok:not_monitoring";
        _unregisterPhoneStateListener();
        _monitoring = false;
        return "ok";
    }

    public String getCallState() {
        if (!hasPermission(Manifest.permission.READ_PHONE_STATE)) {
            return "error:permission_denied:READ_PHONE_STATE";
        }
        int state = _telephonyManager.getCallState();
        switch (state) {
            case TelephonyManager.CALL_STATE_RINGING:  return "ringing";
            case TelephonyManager.CALL_STATE_OFFHOOK:  return "offhook";
            default:                                    return "idle";
        }
    }

    public String setMicMute(boolean mute) {
        try {
            _audioManager.setMicrophoneMute(mute);
            return "ok:" + (mute ? "muted" : "unmuted");
        } catch (Exception e) {
            return "error:" + e.getMessage();
        }
    }

    public String setSpeakerphone(boolean on) {
        try {
            _audioManager.setMode(on
                ? AudioManager.MODE_IN_CALL
                : AudioManager.MODE_IN_COMMUNICATION);
            _audioManager.setSpeakerphoneOn(on);
            return "ok:" + (on ? "speaker" : "earpiece");
        } catch (Exception e) {
            return "error:" + e.getMessage();
        }
    }

    public boolean isDefaultDialer() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            String defaultDialer = _telecomManager.getDefaultDialerPackage();
            return _ctx.getPackageName().equals(defaultDialer);
        }
        return false;
    }

    public void requestDefaultDialer() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent intent = new Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER);
            intent.putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME,
                            _ctx.getPackageName());
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            _ctx.startActivity(intent);
        }
    }

    // ── InCallService bridge ─────────────────────────────────────────────

    private void _wireInCallServiceBridge() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return;

        GhostInCallService.setListener(new GhostInCallService.EventListener() {
            @Override
            public void onIncomingCall(String callId, String number) {
                _activeNumber = number;
                _host.emitTelephonySignal("on_incoming_call", number);
            }

            @Override
            public void onCallStarted(String callId, String number) {
                _activeNumber = number;
                _callStartMs  = System.currentTimeMillis();
                _host.emitTelephonySignal("on_call_started", number);
            }

            @Override
            public void onCallEnded(String callId, long durationMs) {
                long secs = durationMs / 1000;
                _host.emitTelephonySignal("on_call_ended", String.valueOf(secs));
                _activeNumber = "";
                _callStartMs  = 0;
            }

            @Override
            public void onCallStateChanged(String callId, String state) {
                _host.emitTelephonySignal("on_call_state_changed", callId + ":" + state);
            }

            @Override
            public void onAudioRouteChanged(String route) {
                _host.emitTelephonySignal("on_audio_route_changed", route);
            }
        });
    }

    public String answerCallById(String callId) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && GhostInCallService.getInstance() != null) {
            return GhostInCallService.answerCall(callId);
        }
        return answerCall();
    }

    public String endCallById(String callId) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && GhostInCallService.getInstance() != null) {
            return GhostInCallService.disconnectCall(callId);
        }
        return endCall();
    }

    public String holdCall(String callId) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && GhostInCallService.getInstance() != null) {
            return GhostInCallService.holdCall(callId);
        }
        return "error:requires_default_dialer";
    }

    public String unholdCall(String callId) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && GhostInCallService.getInstance() != null) {
            return GhostInCallService.unholdCall(callId);
        }
        return "error:requires_default_dialer";
    }

    public String setAudioRoute(String route) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && GhostInCallService.getInstance() != null) {
            return GhostInCallService.setAudioRoute(route);
        }
        return setSpeakerphone("SPEAKER".equalsIgnoreCase(route));
    }

    public String listActiveCalls() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && GhostInCallService.getInstance() != null) {
            return GhostInCallService.listCalls();
        }
        return "[]";
    }

    public boolean isInCallServiceBound() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return GhostInCallService.getInstance() != null;
        }
        return false;
    }

    // ════════════════════════════════════════════════════════════════════════
    // PERMISSION RESULT — call from GhostKVPlugin.onRequestPermissionsResult
    // ════════════════════════════════════════════════════════════════════════

    public void onPermissionResult(int requestCode, String[] permissions, int[] grantResults) {
        boolean granted = grantResults.length > 0
                       && grantResults[0] == PackageManager.PERMISSION_GRANTED;

        if (requestCode == RC_CALL_PHONE) {
            if (granted && _pendingCall) {
                _pendingCall = false;
                _placeCall(_pendingNumber);
                _pendingNumber = "";
            } else {
                _host.emitTelephonySignal("on_permission_denied", "CALL_PHONE");
            }
        } else if (requestCode == RC_ANSWER_CALLS) {
            if (granted && _pendingAnswer) {
                _pendingAnswer = false;
                _acceptRingingCall();
            } else {
                _host.emitTelephonySignal("on_permission_denied", "ANSWER_PHONE_CALLS");
            }
        } else if (requestCode == RC_PHONE_STATE) {
            if (granted) {
                _registerPhoneStateListener();
                _monitoring = true;
            } else {
                _host.emitTelephonySignal("on_permission_denied", "READ_PHONE_STATE");
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ════════════════════════════════════════════════════════════════════════

    public void onDestroy() {
        stopCallMonitor();
    }

    // ════════════════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ════════════════════════════════════════════════════════════════════════

    private String _placeCall(String number) {
        try {
            String clean = number.replaceAll("[^0-9+*#]", "");
            if (clean.isEmpty()) return "error:invalid_number";

            Uri uri = Uri.fromParts("tel", clean, null);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Bundle extras = new Bundle();
                _telecomManager.placeCall(uri, extras);
            } else {
                Intent intent = new Intent(Intent.ACTION_CALL, uri);
                intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                _ctx.startActivity(intent);
            }
            return "ok";
        } catch (SecurityException e) {
            Log.e(TAG, "_placeCall security", e);
            return "error:permission_denied";
        } catch (Exception e) {
            Log.e(TAG, "_placeCall failed", e);
            return "error:" + e.getMessage();
        }
    }

    private String _acceptRingingCall() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return "error:api_level:requires_android_8";
        }
        try {
            _telecomManager.acceptRingingCall();
            return "ok";
        } catch (Exception e) {
            Log.e(TAG, "_acceptRingingCall failed", e);
            return "error:" + e.getMessage();
        }
    }

    @SuppressWarnings("deprecation")
    private void _registerPhoneStateListener() {
        // Use deprecated PhoneStateListener on all API levels — still works
        _phoneStateListener = new PhoneStateListener() {
            @Override
            public void onCallStateChanged(int state, String number) {
                _handleCallStateChange(state, number);
            }
        };
        _telephonyManager.listen(_phoneStateListener,
            PhoneStateListener.LISTEN_CALL_STATE);
    }

    @SuppressWarnings("deprecation")
    private void _unregisterPhoneStateListener() {
        if (_phoneStateListener != null) {
            _telephonyManager.listen(_phoneStateListener,
                PhoneStateListener.LISTEN_NONE);
            _phoneStateListener = null;
        }
    }

    private void _handleCallStateChange(int state, String number) {
        switch (state) {
            case TelephonyManager.CALL_STATE_RINGING:
                _activeNumber = (number != null) ? number : "unknown";
                Log.d(TAG, "RINGING: " + _activeNumber);
                _host.emitTelephonySignal("on_incoming_call", _activeNumber);
                break;

            case TelephonyManager.CALL_STATE_OFFHOOK:
                if (_callStartMs == 0) {
                    _callStartMs = System.currentTimeMillis();
                }
                Log.d(TAG, "OFFHOOK: " + _activeNumber);
                _host.emitTelephonySignal("on_call_started", _activeNumber);
                break;

            case TelephonyManager.CALL_STATE_IDLE:
                long durationSec = _callStartMs > 0
                    ? (System.currentTimeMillis() - _callStartMs) / 1000
                    : 0;
                Log.d(TAG, "IDLE: duration=" + durationSec + "s");
                _host.emitTelephonySignal("on_call_ended", String.valueOf(durationSec));
                _activeNumber = "";
                _callStartMs  = 0;
                break;
        }
    }

    private boolean hasPermission(String permission) {
        return ContextCompat.checkSelfPermission(_ctx, permission)
               == PackageManager.PERMISSION_GRANTED;
    }

    private void requestPermission(String permission, int requestCode) {
        Activity activity = _host.getHostActivity();
        if (activity != null) {
            activity.requestPermissions(new String[]{permission}, requestCode);
        }
    }
}
