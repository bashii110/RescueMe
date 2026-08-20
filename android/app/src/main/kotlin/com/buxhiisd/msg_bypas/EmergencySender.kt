package com.buxhiisd.msg_bypas

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.util.Log
import androidx.core.content.ContextCompat
import org.json.JSONArray

/**
 * Fully native emergency alert pipeline — no dependency on Flutter,
 * MethodChannels, or MainActivity being alive.
 *
 * AccidentMonitoringService / AlarmForegroundService can call this
 * directly, so SMS + calls still go out even if the app process was
 * killed and only the background service was resurrected by the OS,
 * BootReceiver, or the AlarmManager restart.
 */
object EmergencySender {

    private const val TAG = "EmergencySender"

    // Must match what Flutter's shared_preferences plugin stores under
    // the hood: key is prefixed with "flutter.", and string lists are
    // JSON-encoded with a special base64 marker prefix so the plugin can
    // tell them apart from plain strings.
    private const val CONTACTS_KEY = "flutter.emergency_contacts"
    private const val LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"

    data class Contact(val name: String, val phone: String)

    fun sendEmergencyAlerts(context: Context) {
        Log.d(TAG, "🚨 Native emergency alert pipeline starting")

        val contacts = readContacts(context)
        if (contacts.isEmpty()) {
            Log.e(TAG, "❌ No emergency contacts found — nothing to send")
            return
        }

        val message = buildMessage(context)

        for (contact in contacts) {
            sendSms(context, contact.phone, message)
        }

        // Space calls out so each one actually gets a chance to ring
        // before the next fires — mirrors CallService's 30s spacing.
        val handler = Handler(Looper.getMainLooper())
        contacts.forEachIndexed { index, contact ->
            handler.postDelayed({ makeCall(context, contact.phone) }, index * 30_000L)
        }
    }

    // ── Contacts ─────────────────────────────────────────────────────────
    private fun readContacts(context: Context): List<Contact> {
        return try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString(CONTACTS_KEY, null) ?: return emptyList()

            val json = if (raw.startsWith(LIST_PREFIX)) raw.removePrefix(LIST_PREFIX) else raw
            val array = JSONArray(json)

            val result = mutableListOf<Contact>()
            for (i in 0 until array.length()) {
                val entry = array.getString(i) // "name|phone"
                val parts = entry.split("|")
                if (parts.size >= 2 && parts[1].isNotBlank()) {
                    result.add(Contact(parts[0], parts[1]))
                }
            }
            Log.d(TAG, "✅ Loaded ${result.size} emergency contact(s)")
            result
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to read emergency contacts: ${e.message}")
            emptyList()
        }
    }

    // ── Location ─────────────────────────────────────────────────────────
    private fun getLastKnownLocation(context: Context): Location? {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) return null

        return try {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            var best: Location? = null
            for (provider in lm.getProviders(true)) {
                val loc = lm.getLastKnownLocation(provider) ?: continue
                if (best == null || loc.accuracy < best!!.accuracy) best = loc
            }
            best
        } catch (e: Exception) {
            Log.e(TAG, "❌ Location lookup failed: ${e.message}")
            null
        }
    }

    private fun buildMessage(context: Context): String {
        val location = getLastKnownLocation(context)
        val sb = StringBuilder()
        sb.append("🚨 EMERGENCY ALERT 🚨\n\nAccident detected!\n\n")

        if (location != null) {
            val lat = location.latitude
            val lon = location.longitude
            sb.append("📍 Location:\n")
            sb.append("Lat: ${"%.6f".format(lat)}\n")
            sb.append("Lon: ${"%.6f".format(lon)}\n\n")
            sb.append("🗺 View on map:\nhttps://maps.google.com/?q=$lat,$lon\n\n")
        } else {
            sb.append("Unable to get precise location. Please send help!\n\n")
        }

        sb.append("Time: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(java.util.Date())}")
        return sb.toString()
    }

    // ── SMS ──────────────────────────────────────────────────────────────
    private fun sendSms(context: Context, phoneNumber: String, message: String) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "❌ No SEND_SMS permission — cannot alert $phoneNumber")
            return
        }

        try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            if (message.length > 160) {
                val parts = smsManager.divideMessage(message)
                smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(phoneNumber, null, message, null, null)
            }
            Log.d(TAG, "✅ Emergency SMS dispatched to $phoneNumber")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to send SMS to $phoneNumber: ${e.message}")
        }
    }

    // ── Calls ────────────────────────────────────────────────────────────
    private fun makeCall(context: Context, phoneNumber: String) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "❌ No CALL_PHONE permission — cannot call $phoneNumber")
            return
        }

        try {
            val intent = Intent(Intent.ACTION_CALL).apply {
                data = Uri.parse("tel:$phoneNumber")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            Log.d(TAG, "✅ Emergency call initiated to $phoneNumber")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to call $phoneNumber: ${e.message}")
        }
    }
}