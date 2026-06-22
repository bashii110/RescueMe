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

    // Detection tracking
    private var highAccelerationCount = 0
    private val recentAccelerations = mutableListOf<Double>()

    // Thresholds
    private val STRICT_ACCEL_THRESHOLD = 45.0
    private val STRICT_GYRO_THRESHOLD = 4.0
    private val GYROSCOPE_THRESHOLD = 3.0
    private val REQUIRED_SAMPLES = 2
    private val SMOOTH_WINDOW = 5

    private var isAccidentDetected = false

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "accident_monitoring_channel"
        private const val CHANNEL_NAME = "Accident Monitoring"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d("AccidentService", "🚀 Service created")

        // CRITICAL: Acquire wake lock for OPPO devices
        acquireWakeLock()

        // Initialize sensors
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        if (accelerometer == null) {
            Log.e("AccidentService", "❌ No accelerometer found!")
        }
        if (gyroscope == null) {
            Log.e("AccidentService", "❌ No gyroscope found!")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("AccidentService", "🎯 Service started")

        // Create notification channel
        createNotificationChannel()

        // Start foreground with OPPO-optimized notification
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)

        // Register sensors
        registerSensors()

        // Return STICKY to ensure service restarts if killed
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
            val importance = NotificationManager.IMPORTANCE_HIGH // HIGH for OPPO
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, importance).apply {
                description = "Monitors for accidents in background"
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
            Log.d("AccidentService", "✅ Notification channel created")
        }
    }

    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            else
                PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🛡️ Rescue Me Active")
            .setContentText("Monitoring for accidents in background")
            .setSmallIcon(android.R.drawable.ic_menu_compass) // Use your app icon
            .setContentIntent(pendingIntent)
            .setOngoing(true) // Make it persistent
            .setPriority(NotificationCompat.PRIORITY_HIGH) // HIGH priority for OPPO
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .build()
    }

    private fun registerSensors() {
        try {
            accelerometer?.let {
                sensorManager.registerListener(
                    this,
                    it,
                    SensorManager.SENSOR_DELAY_NORMAL
                )
                Log.d("AccidentService", "✅ Accelerometer registered")
            }

            gyroscope?.let {
                sensorManager.registerListener(
                    this,
                    it,
                    SensorManager.SENSOR_DELAY_NORMAL
                )
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

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed for this use case
    }

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

        // Add to smoothing window
        recentAccelerations.add(accelerationMagnitude)
        if (recentAccelerations.size > SMOOTH_WINDOW) {
            recentAccelerations.removeAt(0)
        }

        if (recentAccelerations.isEmpty()) return

        val avgAccel = recentAccelerations.average()

        // Early return if too low
        if (avgAccel < 10.0) return
        if (gyroscopeMagnitude < 0.3) return

        // Count high acceleration events
        // Count high acceleration events
        if (avgAccel > STRICT_ACCEL_THRESHOLD) {
            highAccelerationCount++
        } else {
            highAccelerationCount = 0
        }

        // STRICT AND: acceleration and rotation must both exceed
        // their threshold at the same time before triggering.
        // (No microphone access natively, so noise leg is not evaluated here.)
        val accelOk = avgAccel > STRICT_ACCEL_THRESHOLD
        val gyroOk = gyroscopeMagnitude > STRICT_GYRO_THRESHOLD

        if (accelOk && gyroOk) {
            triggerAccident()
        }
    }

    private fun triggerAccident() {
        isAccidentDetected = true
        highAccelerationCount = 0
        recentAccelerations.clear()

        Log.d("AccidentService", "🚨 ACCIDENT DETECTED IN BACKGROUND!")

        // Update notification
        updateNotificationForAccident()

        // Launch MainActivity
        launchMainActivity()

        // Broadcast to MainActivity if it's running
        val intent = Intent("ACCIDENT_DETECTED_BACKGROUND")
        sendBroadcast(intent)

        // Reset detection after 30 seconds
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

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification)
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

    override fun onDestroy() {
        super.onDestroy()
        Log.d("AccidentService", "🛑 Service destroyed")

        // Unregister sensors
        sensorManager.unregisterListener(this)

        // Release wake lock
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }

        // CRITICAL: Restart service for OPPO devices
        val restartIntent = Intent(applicationContext, AccidentMonitoringService::class.java)
        val pendingIntent = PendingIntent.getService(
            applicationContext,
            1,
            restartIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT
            else
                PendingIntent.FLAG_ONE_SHOT
        )

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.set(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + 1000,
            pendingIntent
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null
}