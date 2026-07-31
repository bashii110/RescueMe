package com.buxhiisd.msg_bypas

import android.app.*
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlin.math.abs
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
    private val STRICT_ACCEL_THRESHOLD = 45.0   // m/s²
    private val STRICT_GYRO_THRESHOLD  = 4.0    // rad/s
    private val DETECTION_WINDOW_MS    = 2000L  // 2 seconds

    // Timestamps — each records when that sensor last crossed its threshold.
    // Both must have fired within DETECTION_WINDOW_MS to confirm an accident.
    // Null means that sensor has not yet triggered in the current window.
    private var accelTriggerTime: Long? = null
    private var gyroTriggerTime:  Long? = null

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
    // An accident is confirmed only when BOTH timestamps exist AND the spread
    // between them is within DETECTION_WINDOW_MS (2 seconds).
    //
    // Timestamps older than the window are expired automatically — this ensures
    // a single-sensor spike from 5 seconds ago can never combine with a fresh
    // spike today to create a false trigger.
    //
    // No order is enforced: gyro may fire before accel or vice versa, which
    // correctly handles all real-world crash geometries.
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
        //    If accel spiked 5 s ago but gyro hasn't fired yet, that
        //    accel event is irrelevant — clear it and wait for a fresh one.
        accelTriggerTime?.let { if (now - it > DETECTION_WINDOW_MS) accelTriggerTime = null }
        gyroTriggerTime?.let  { if (now - it > DETECTION_WINDOW_MS) gyroTriggerTime  = null }

        // ── Step 2: Record a fresh timestamp if the sensor crosses its threshold.
        if (avgAccel          > STRICT_ACCEL_THRESHOLD) accelTriggerTime = now
        if (gyroscopeMagnitude > STRICT_GYRO_THRESHOLD) gyroTriggerTime  = now

        // ── Step 3: Both must have triggered to proceed.
        val at = accelTriggerTime ?: return
        val gt = gyroTriggerTime  ?: return

        // ── Step 4: Check the spread fits within the detection window.
        val spreadMs = abs(at - gt)
        if (spreadMs <= DETECTION_WINDOW_MS) {
            // ✅ Accident confirmed — both sensors fired within the window.
            accelTriggerTime = null
            gyroTriggerTime  = null
            triggerAccident()
        }
    }

    private fun resetTriggerTimestamps() {
        accelTriggerTime = null
        gyroTriggerTime  = null
    }

    private fun triggerAccident() {
        isAccidentDetected = true
        recentAccelerations.clear()
        resetTriggerTimestamps() // belt-and-suspenders

        Log.d("AccidentService", "🚨 ACCIDENT DETECTED IN BACKGROUND!")

        updateNotificationForAccident()
        launchMainActivity()

        // Broadcast to MainActivity if it's running
        sendBroadcast(Intent("ACCIDENT_DETECTED_BACKGROUND"))

        // Reset detection flag after 30 seconds so the service
        // can detect a subsequent accident if needed.
        android.os.Handler(mainLooper).postDelayed({
            isAccidentDetected = false
            Log.d("AccidentService", "✅ Detection reset")
        }, 30000)
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