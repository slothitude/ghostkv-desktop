package com.slothitude.ghostkv;

import android.annotation.SuppressLint;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.telecom.Call;
import android.telecom.CallAudioState;
import android.telecom.InCallService;
import android.telecom.VideoProfile;
import android.util.Log;

import java.util.concurrent.ConcurrentHashMap;

/**
 * GhostInCallService — gives the agent full telephony control.
 *
 * When GhostKV is set as the default phone app, Android routes ALL call events
 * here — incoming, outgoing, held, disconnected. The service bridges back to
 * GhostKVPlugin via a static singleton bus so GDScript can drive decisions.
 *
 * AndroidManifest.xml (inside <application>):
 *
 *   <service
 *       android:name=".GhostInCallService"
 *       android:permission="android.permission.BIND_INCALL_SERVICE"
 *       android:exported="true">
 *       <intent-filter>
 *           <action android:name="android.telecom.InCallService" />
 *       </intent-filter>
 *       <meta-data
 *           android:name="android.telecom.IN_CALL_SERVICE_UI"
 *           android:value="true" />
 *       <meta-data
 *           android:name="android.telecom.IN_CALL_SERVICE_RINGING"
 *           android:value="true" />
 *   </service>
 *
 * Signal bus (GhostKVPlugin wires these):
 *   "on_incoming_call"        (String number)
 *   "on_call_started"         (String number)
 *   "on_call_ended"           (String duration_seconds)
 *   "on_call_state_changed"   (String callId, String state)
 *   "on_audio_route_changed"  (String route)   e.g. "EARPIECE", "SPEAKER", "BLUETOOTH"
 *
 * Commands from GDScript via GhostTelephony:
 *   answerCall()   → GhostInCallService.answerCall(callId)
 *   endCall()      → GhostInCallService.endCall(callId)
 *   holdCall()     → GhostInCallService.holdCall(callId)
 *   setRoute()     → GhostInCallService.setAudioRoute(route)
 */
public class GhostInCallService extends InCallService {

    private static final String TAG = "GhostInCallService";

    // ── Static bridge — GhostKVPlugin talks to us via this ─────────────────
    private static GhostInCallService _instance = null;
    private static EventListener      _listener  = null;

    public interface EventListener {
        void onIncomingCall(String callId, String number);
        void onCallStarted(String callId, String number);
        void onCallEnded(String callId, long durationMs);
        void onCallStateChanged(String callId, String state);
        void onAudioRouteChanged(String route);
    }

    /** Called by GhostKVPlugin on startup to wire the event bus. */
    public static void setListener(EventListener l) {
        _listener = l;
    }

    /** Returns the live service instance, or null if not bound. */
    public static GhostInCallService getInstance() {
        return _instance;
    }

    // ── Call tracking ────────────────────────────────────────────────────────
    // callId → {call, startTimeMs, number}
    private final ConcurrentHashMap<String, CallRecord> _calls = new ConcurrentHashMap<>();
    private final Handler _mainHandler = new Handler(Looper.getMainLooper());

    private AudioManager       _audioManager;
    private AudioFocusRequest  _focusRequest;

    // ════════════════════════════════════════════════════════════════════════
    // InCallService lifecycle
    // ════════════════════════════════════════════════════════════════════════

    @Override
    public void onCreate() {
        super.onCreate();
        _instance     = this;
        _audioManager = (AudioManager) getSystemService(AUDIO_SERVICE);
        Log.d(TAG, "GhostInCallService created");
    }

    @Override
    public void onDestroy() {
        _instance = null;
        _abandonAudioFocus();
        Log.d(TAG, "GhostInCallService destroyed");
        super.onDestroy();
    }

    // ════════════════════════════════════════════════════════════════════════
    // Call events — Android calls these on the main thread
    // ════════════════════════════════════════════════════════════════════════

    @Override
    public void onCallAdded(Call call) {
        String callId = callIdOf(call);
        String number = numberOf(call);
        Log.d(TAG, "onCallAdded id=" + callId + " number=" + number
              + " state=" + stateLabel(call.getState()));

        CallRecord rec = new CallRecord(call, number);
        _calls.put(callId, rec);

        // Register our callback for state changes on this specific call
        call.registerCallback(_callCallback);

        int state = call.getState();

        if (state == Call.STATE_RINGING) {
            _requestAudioFocus();
            if (_listener != null) _listener.onIncomingCall(callId, number);

        } else if (state == Call.STATE_DIALING || state == Call.STATE_CONNECTING) {
            // Outgoing call initiated by agent
            _requestAudioFocus();
            if (_listener != null) _listener.onCallStarted(callId, number);
        }
    }

    @Override
    public void onCallRemoved(Call call) {
        String callId = callIdOf(call);
        CallRecord rec = _calls.remove(callId);
        call.unregisterCallback(_callCallback);

        long duration = (rec != null && rec.startMs > 0)
            ? System.currentTimeMillis() - rec.startMs : 0;

        Log.d(TAG, "onCallRemoved id=" + callId + " duration=" + duration + "ms");

        if (_calls.isEmpty()) _abandonAudioFocus();
        if (_listener != null) _listener.onCallEnded(callId, duration);
    }

    @Override
    public void onCallAudioStateChanged(CallAudioState state) {
        String route = routeLabel(state.getRoute());
        Log.d(TAG, "audioRouteChanged → " + route);
        if (_listener != null) _listener.onAudioRouteChanged(route);
    }

    // ── Per-call state callback ──────────────────────────────────────────────
    private final Call.Callback _callCallback = new Call.Callback() {
        @Override
        public void onStateChanged(Call call, int newState) {
            String callId = callIdOf(call);
            String label  = stateLabel(newState);
            Log.d(TAG, "onStateChanged id=" + callId + " → " + label);

            CallRecord rec = _calls.get(callId);

            switch (newState) {
                case Call.STATE_ACTIVE:
                    if (rec != null && rec.startMs == 0) {
                        rec.startMs = System.currentTimeMillis();
                    }
                    if (_listener != null)
                        _listener.onCallStarted(callId, rec != null ? rec.number : "");
                    break;

                case Call.STATE_DISCONNECTED:
                    // onCallRemoved will fire shortly — handled there
                    break;

                case Call.STATE_HOLDING:
                case Call.STATE_RINGING:
                case Call.STATE_DIALING:
                    break;
            }

            if (_listener != null) _listener.onCallStateChanged(callId, label);
        }

        @Override
        public void onDetailsChanged(Call call, Call.Details details) {
            // Number may resolve after initial onCallAdded (e.g. contact lookup)
            String callId = callIdOf(call);
            CallRecord rec = _calls.get(callId);
            if (rec != null) {
                rec.number = numberOf(call);
            }
        }
    };

    // ════════════════════════════════════════════════════════════════════════
    // COMMAND API — called from GhostTelephony (static dispatch)
    // ════════════════════════════════════════════════════════════════════════

    /** Answer the first ringing call, or a specific call by ID. */
    public static String answerCall(String callId) {
        GhostInCallService svc = _instance;
        if (svc == null) return "error:service_not_bound";

        Call call = svc._findCall(callId, Call.STATE_RINGING);
        if (call == null) call = svc._findAnyRinging();
        if (call == null) return "error:no_ringing_call";

        call.answer(VideoProfile.STATE_AUDIO_ONLY);
        return "ok";
    }

    /** Disconnect a call by ID, or the first active/ringing call. */
    public static String disconnectCall(String callId) {
        GhostInCallService svc = _instance;
        if (svc == null) return "error:service_not_bound";

        Call call = svc._findCall(callId, -1);
        if (call == null) call = svc._findFirst();
        if (call == null) return "error:no_call";

        call.disconnect();
        return "ok";
    }

    /** Hold a call. */
    public static String holdCall(String callId) {
        GhostInCallService svc = _instance;
        if (svc == null) return "error:service_not_bound";

        Call call = svc._findCall(callId, Call.STATE_ACTIVE);
        if (call == null) return "error:no_active_call";
        call.hold();
        return "ok";
    }

    /** Unhold a call. */
    public static String unholdCall(String callId) {
        GhostInCallService svc = _instance;
        if (svc == null) return "error:service_not_bound";

        Call call = svc._findCall(callId, Call.STATE_HOLDING);
        if (call == null) return "error:no_held_call";
        call.unhold();
        return "ok";
    }

    /**
     * Set audio route. route = "EARPIECE" | "SPEAKER" | "BLUETOOTH" | "WIRED"
     */
    public static String setAudioRoute(String route) {
        GhostInCallService svc = _instance;
        if (svc == null) return "error:service_not_bound";

        int routeCode;
        switch (route.toUpperCase()) {
            case "SPEAKER":   routeCode = CallAudioState.ROUTE_SPEAKER;    break;
            case "BLUETOOTH": routeCode = CallAudioState.ROUTE_BLUETOOTH;  break;
            case "WIRED":     routeCode = CallAudioState.ROUTE_WIRED_HEADSET; break;
            default:          routeCode = CallAudioState.ROUTE_EARPIECE;   break;
        }
        svc.setAudioRoute(routeCode);
        return "ok:" + route;
    }

    /** List all active call IDs and their states. */
    public static String listCalls() {
        GhostInCallService svc = _instance;
        if (svc == null) return "[]";

        StringBuilder sb = new StringBuilder("[");
        for (java.util.Map.Entry<String, CallRecord> e : svc._calls.entrySet()) {
            if (sb.length() > 1) sb.append(",");
            sb.append("{\"id\":\"").append(e.getKey())
              .append("\",\"number\":\"").append(e.getValue().number)
              .append("\",\"state\":\"")
              .append(stateLabel(e.getValue().call.getState()))
              .append("\"}");
        }
        sb.append("]");
        return sb.toString();
    }

    // ════════════════════════════════════════════════════════════════════════
    // AUDIO FOCUS
    // ════════════════════════════════════════════════════════════════════════

    @SuppressLint("NewApi")
    private void _requestAudioFocus() {
        if (_audioManager == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            _focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build())
                .setAcceptsDelayedFocusGain(false)
                .build();
            _audioManager.requestAudioFocus(_focusRequest);
        } else {
            //noinspection deprecation
            _audioManager.requestAudioFocus(null,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT);
        }
        _audioManager.setMode(AudioManager.MODE_IN_CALL);
    }

    private void _abandonAudioFocus() {
        if (_audioManager == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && _focusRequest != null) {
            _audioManager.abandonAudioFocusRequest(_focusRequest);
            _focusRequest = null;
        } else {
            //noinspection deprecation
            _audioManager.abandonAudioFocus(null);
        }
        _audioManager.setMode(AudioManager.MODE_NORMAL);
    }

    // ════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════════════════

    private Call _findCall(String callId, int requiredState) {
        if (callId == null || callId.isEmpty()) return null;
        CallRecord rec = _calls.get(callId);
        if (rec == null) return null;
        if (requiredState >= 0 && rec.call.getState() != requiredState) return null;
        return rec.call;
    }

    private Call _findAnyRinging() {
        for (CallRecord r : _calls.values()) {
            if (r.call.getState() == Call.STATE_RINGING) return r.call;
        }
        return null;
    }

    private Call _findFirst() {
        for (CallRecord r : _calls.values()) return r.call;
        return null;
    }

    private static String callIdOf(Call call) {
        // Use object identity hash as stable ID within this session
        return String.valueOf(System.identityHashCode(call));
    }

    private static String numberOf(Call call) {
        try {
            Call.Details d = call.getDetails();
            if (d == null) return "unknown";
            android.net.Uri handle = d.getHandle();
            if (handle == null) return "unknown";
            String num = handle.getSchemeSpecificPart();
            return (num != null && !num.isEmpty()) ? num : "unknown";
        } catch (Exception e) {
            return "unknown";
        }
    }

    private static String stateLabel(int state) {
        switch (state) {
            case Call.STATE_ACTIVE:        return "active";
            case Call.STATE_RINGING:       return "ringing";
            case Call.STATE_DIALING:       return "dialing";
            case Call.STATE_CONNECTING:    return "connecting";
            case Call.STATE_HOLDING:       return "holding";
            case Call.STATE_DISCONNECTED:  return "disconnected";
            case Call.STATE_NEW:           return "new";
            default:                       return "unknown_" + state;
        }
    }

    private static String routeLabel(int route) {
        switch (route) {
            case CallAudioState.ROUTE_EARPIECE:       return "EARPIECE";
            case CallAudioState.ROUTE_SPEAKER:        return "SPEAKER";
            case CallAudioState.ROUTE_BLUETOOTH:      return "BLUETOOTH";
            case CallAudioState.ROUTE_WIRED_HEADSET:  return "WIRED";
            default:                                   return "UNKNOWN";
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // INNER CLASSES
    // ════════════════════════════════════════════════════════════════════════

    private static class CallRecord {
        final Call call;
        String     number;
        long       startMs = 0;

        CallRecord(Call call, String number) {
            this.call   = call;
            this.number = number;
        }
    }
}
