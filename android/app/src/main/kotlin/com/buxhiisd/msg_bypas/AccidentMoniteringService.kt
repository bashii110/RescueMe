package com.buxhiisd.msg_bypas

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import kotlin.math.log10
import kotlin.math.sqrt

class AccidentMonitoringService : Service(), SensorEventListener {

    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null

    private var wakeLock: PowerManager.WakeLock? = null

    // Sensor data
    private var accelerateX = 0.0
    private var accelerateY = 0.0
    private var accelerateZ = 0.0
    private var gyroscopeX = 0.0
    private var gyroscopeY = 0.0
    private var gyroscopeZ = 0.0

    // Smoothing
    private val recentAccelerations = mutableListOf<Double>()
    private val SMOOTH_WINDOW = 5

    // ── Detection thresholds ──────────────────────────────────────────────
    // NOTE: STRICT_NOISE_THRESHOLD is expressed in dB using this service's own
    // RMS-based calculation (see computeDecibels()), which is NOT guaranteed to
    // read on the same scale as the Flutter-side noise_meter package's
    // meanDecibel. Calibrate this value against a real device before relying
    // on it — don't assume 90.0 here means the same loudness as 90.0 in Dart.
    private val STRICT_ACCEL_THRESHOLD = 45.0   // m/s²
    private val STRICT_GYRO_THRESHOLD  = 4.0    // rad/s
    private val STRICT_NOISE_THRESHOLD = 82.0   // dB (native RMS calc — see note above)
    private val DETECTION_WINDOW_MS    = 2000L  // 2 seconds

    // Timestamps — each records when that sensor last crossed its threshold.
    // All three must have fired within DETECTION_WINDOW_MS to confirm an accident.
    // Null means that sensor has not yet triggered in the current window.
    private var accelTriggerTime: Long? = null
    private var gyroTriggerTime:  Long? = null
    private var noiseTriggerTime: Long? = null

    // ── Noise (microphone) monitoring ───────────────────────────────────────
    // Android has no push-based "noise sensor" like it does for accel/gyro, so
    // this reads raw PCM audio off a background thread and computes dB itself.
    private var audioRecord: AudioRecord? = null
    private var noiseMonitoringThread: Thread? = null
    @Volatile private var isRecordingNoise = false
    private val NOISE_SAMPLE_RATE = 44100
    private val noiseBufferSize = AudioRecord.getMinBufferSize(
        NOISE_SAMPLE_RATE,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT
    )

    private var isAccidentDetected = false

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID      = "accident_monitoring_channel"
        private const val CHANNEL_NAME    = "Accident Monitoring"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d("AccidentService", "🚀 Service created")

        acquireWakeLock()

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope     = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        if (accelerometer == null) Log.e("AccidentService", "❌ No accelerometer found!")
        if (gyroscope     == null) Log.e("AccidentService", "❌ No gyroscope found!")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("AccidentService", "🎯 Service started")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        registerSensors()
        startNoiseMonitoring()
        return START_STICKY
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "RescueMe::AccidentMonitorWakeLock"
            ).apply {
                acquire(24 * 60 * 60 * 1000L) // 24 hours
            }
            Log.d("AccidentService", "✅ Wake lock acquired")
        } catch (e: Exception) {
            Log.e("AccidentService", "❌ Failed to acquire wake lock: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description        = "Monitors for accidents in background"
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
            Log.d("AccidentService", "✅ Notification channel created")
        }
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            else
                PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🛡️ Rescue Me Active")
            .setContentText("Monitoring for accidents in background")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .build()
    }

    private fun registerSensors() {
        try {
            accelerometer?.let {
                sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
                Log.d("AccidentService", "✅ Accelerometer registered")
            }
            gyroscope?.let {
                sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
                Log.d("AccidentService", "✅ Gyroscope registered")
            }
        } catch (e: Exception) {
            Log.e("AccidentService", "❌ Failed to register sensors: ${e.message}")
        }
    }

    // ── Noise monitoring (mirrors registerSensors()'s role, but for the mic) ─
    //
    // There's no listener-based API for audio like there is for accel/gyro,
    // so this opens a raw AudioRecord stream and polls it continuously on a
    // dedicated background thread, computing an RMS-based dB value per chunk.
    //
    // Fails gracefully: if RECORD_AUDIO isn't granted, or AudioRecord can't
    // initialize (already in use by another app, hardware unavailable, etc.),
    // this logs and returns — accident detection then simply falls back to
    // the existing 2-signal (accel + gyro) logic, same as before this feature
    // was added.
    private fun startNoiseMonitoring() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            Log.e("AccidentService", "❌ RECORD_AUDIO not granted — noise detection disabled, falling back to accel+gyro only")
            return
        }

        if (noiseBufferSize <= 0) {
            Log.e("AccidentService", "❌ Invalid AudioRecord buffer size — noise detection disabled")
            return
        }

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                NOISE_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                noiseBufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e("AccidentService", "❌ AudioRecord failed to initialize — noise detection disabled")
                audioRecord?.release()
                audioRecord = null
                return
            }

            audioRecord?.startRecording()
            isRecordingNoise = true

            noiseMonitoringThread = Thread {
                val buffer = ShortArray(noiseBufferSize)
                while (isRecordingNoise) {
                    val record = audioRecord ?: break
                    val read = record.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        val db = computeDecibels(buffer, read)
                        if (db > STRICT_NOISE_THRESHOLD) {
                            noiseTriggerTime = System.currentTimeMillis()
                        }
                        // checkForAccident() is otherwise only called from
                        // onSensorChanged; call it here too so a noise spike
                        // can complete a pending accel+gyro match without
                        // waiting for the next motion event.
                        checkForAccident()
                    }
                }
            }.apply {
                isDaemon = true
                start()
            }

            Log.d("AccidentService", "✅ Noise monitoring started")
        } catch (e: Exception) {
            Log.e("AccidentService", "❌ Failed to start noise monitoring: ${e.message}")
            isRecordingNoise = false
            audioRecord?.release()
            audioRecord = null
        }
    }

    private fun stopNoiseMonitoring() {
        isRecordingNoise = false
        try {
            noiseMonitoringThread?.join(500)
        } catch (e: InterruptedException) {
            Log.e("AccidentService", "Noise thread join interrupted: ${e.message}")
        }
        noiseMonitoringThread = null

        try {
            audioRecord?.stop()
        } catch (e: Exception) {
            // stop() throws if recording never actually started — safe to ignore
        }
        audioRecord?.release()
        audioRecord = null
        Log.d("AccidentService", "🛑 Noise monitoring stopped")
    }

    // Standard RMS → dB SPL-style conversion for 16-bit PCM samples.
    // This is a relative loudness measure, not a calibrated SPL reading —
    // see the STRICT_NOISE_THRESHOLD note above regarding cross-checking
    // against the Flutter-side noise_meter scale.
    private fun computeDecibels(buffer: ShortArray, readSize: Int): Double {
        var sumSquares = 0.0
        for (i in 0 until readSize) {
            sumSquares += (buffer[i] * buffer[i]).toDouble()
        }
        val rms = sqrt(sumSquares / readSize)
        if (rms <= 0.0) return 0.0
        return 20 * log10(rms)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                accelerateX = event.values[0].toDouble()
                accelerateY = event.values[1].toDouble()
                accelerateZ = event.values[2].toDouble()
                checkForAccident()
            }
            Sensor.TYPE_GYROSCOPE -> {
                gyroscopeX = event.values[0].toDouble()
                gyroscopeY = event.values[1].toDouble()
                gyroscopeZ = event.values[2].toDouble()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { /* not needed */ }

    // ── Core detection logic ──────────────────────────────────────────────
    //
    // Each sensor independently records the last time it crossed its threshold.
    // An accident is confirmed only when ALL THREE timestamps exist AND the
    // spread between the oldest and newest is within DETECTION_WINDOW_MS
    // (2 seconds) — same model as the Dart-side foreground detector.
    //
    // Timestamps older than the window are expired automatically — this ensures
    // a single-sensor spike from 5 seconds ago can never combine with a fresh
    // spike today to create a false trigger.
    //
    // No order is enforced: any of the three may fire first, which correctly
    // handles all real-world crash geometries.
    //
    // Called both from onSensorChanged() (motion events) and from the noise
    // monitoring thread (audio chunks), since either could be the signal that
    // completes an already-pending match.
    //
    private fun checkForAccident() {
        if (isAccidentDetected) return

        val accelerationMagnitude = sqrt(
            accelerateX * accelerateX +
                    accelerateY * accelerateY +
                    accelerateZ * accelerateZ
        )
        val gyroscopeMagnitude = sqrt(
            gyroscopeX * gyroscopeX +
                    gyroscopeY * gyroscopeY +
                    gyroscopeZ * gyroscopeZ
        )

        // Smoothing window
        recentAccelerations.add(accelerationMagnitude)
        if (recentAccelerations.size > SMOOTH_WINDOW) recentAccelerations.removeAt(0)
        if (recentAccelerations.isEmpty()) return

        val avgAccel = recentAccelerations.average()

        val now = System.currentTimeMillis()

        // ── Step 1: Expire timestamps outside the detection window.
        //    If accel spiked 5 s ago but the others haven't fired yet, that
        //    accel event is irrelevant — clear it and wait for a fresh one.
        accelTriggerTime?.let { if (now - it > DETECTION_WINDOW_MS) accelTriggerTime = null }
        gyroTriggerTime?.let  { if (now - it > DETECTION_WINDOW_MS) gyroTriggerTime  = null }
        noiseTriggerTime?.let { if (now - it > DETECTION_WINDOW_MS) noiseTriggerTime = null }

        // ── Step 2: Record a fresh timestamp if the sensor crosses its threshold.
        //    (Noise's own timestamp is set directly on the monitoring thread,
        //    since that's where the dB reading is computed.)
        if (avgAccel           > STRICT_ACCEL_THRESHOLD) accelTriggerTime = now
        if (gyroscopeMagnitude > STRICT_GYRO_THRESHOLD)  gyroTriggerTime  = now

        // ── Step 3: All three must have triggered to proceed.
        val at = accelTriggerTime ?: return
        val gt = gyroTriggerTime  ?: return
        val nt = noiseTriggerTime ?: return

        // ── Step 4: Check that all three fall within the detection window —
        //    find the oldest and newest timestamps, spread must be ≤ 2s.
        val oldest = minOf(at, gt, nt)
        val newest = maxOf(at, gt, nt)
        val spreadMs = newest - oldest

        if (spreadMs <= DETECTION_WINDOW_MS) {
            // ✅ Accident confirmed — all three sensors fired within the window.
            resetTriggerTimestamps()
            triggerAccident()
        }
    }

    private fun resetTriggerTimestamps() {
        accelTriggerTime = null
        gyroTriggerTime  = null
        noiseTriggerTime = null
    }

    private fun triggerAccident() {
        isAccidentDetected = true
        recentAccelerations.clear()
        resetTriggerTimestamps()

        Log.d("AccidentService", "🚨 ACCIDENT DETECTED IN BACKGROUND!")

        updateNotificationForAccident()

        // Start the native countdown/alarm directly — no dependency on
        // MainActivity or Flutter being alive. This is what actually sends
        // the SMS/calls if the process was killed.
        startNativeAlarmCountdown()

        // Also try to bring the app forward for the richer in-app experience
        // (siren UI, haptics) when the process is reachable.
        launchMainActivity()
        sendBroadcast(Intent("ACCIDENT_DETECTED_BACKGROUND"))

        android.os.Handler(mainLooper).postDelayed({
            isAccidentDetected = false
            Log.d("AccidentService", "✅ Detection reset")
        }, 30000)
    }

    private fun startNativeAlarmCountdown() {
        val alarmIntent = Intent(this, AlarmForegroundService::class.java)
        alarmIntent.putExtra("duration", 30)
        // No "nativeSendOnFinish" extra → defaults true in AlarmForegroundService,
        // i.e. this service is responsible for sending the alert unless Flutter
        // later restarts it with that flag set to false (see MainActivity).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(alarmIntent)
        } else {
            startService(alarmIntent)
        }
    }

    private fun updateNotificationForAccident() {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🚨 ACCIDENT DETECTED!")
            .setContentText("Tap to respond or auto-alert will trigger")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .build()
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification)
    }

    private fun launchMainActivity() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("accident_detected", true)
            }
            startActivity(intent)
            Log.d("AccidentService", "✅ MainActivity launched")
        } catch (e: Exception) {
            Log.e("AccidentService", "❌ Failed to launch MainActivity: ${e.message}")
        }
    }

    // Checks BOTH SharedPreferences locations, same pattern used by
    // BootReceiver and MainActivity, so this stays consistent regardless
    // of which side (native or Flutter) last wrote the flag.
    private fun isMonitoringStillEnabled(): Boolean {
        val nativePrefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
        val nativeMonitoring = nativePrefs.getBoolean("monitoring_enabled", false)

        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val flutterMonitoring = flutterPrefs.getBoolean("flutter.monitoring_enabled", false)

        return nativeMonitoring || flutterMonitoring
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("AccidentService", "🛑 Service destroyed")

        sensorManager.unregisterListener(this)
        stopNoiseMonitoring()

        wakeLock?.let { if (it.isHeld) it.release() }

        // Only reschedule via AlarmManager (for OEM devices that kill services)
        // if the user hasn't explicitly turned monitoring off. Without this
        // check, tapping "Stop Monitoring" would have no effect — the service
        // would just relaunch itself a second later.
        if (isMonitoringStillEnabled()) {
            val restartIntent = Intent(applicationContext, AccidentMonitoringService::class.java)
            val pendingIntent = PendingIntent.getService(
                applicationContext, 1, restartIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT
                else
                    PendingIntent.FLAG_ONE_SHOT
            )
            (getSystemService(Context.ALARM_SERVICE) as AlarmManager).set(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + 1000,
                pendingIntent
            )
            Log.d("AccidentService", "🔁 Monitoring still enabled — rescheduled restart")
        } else {
            Log.d("AccidentService", "⏸️ Monitoring disabled — not rescheduling restart")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}