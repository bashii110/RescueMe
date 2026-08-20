import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'location_service.dart';

class SMSService {
  static const platform = MethodChannel('com.buxhiisd.msg_bypas/sms');
  static const servicePlatform = MethodChannel('com.buxhiisd.msg_bypas/service');

  /// Check if device is Chinese OEM (Vivo, OPPO, etc.)
  static Future<bool> isChineseOEM() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      return manufacturer.contains('oppo') ||
          manufacturer.contains('vivo') ||
          manufacturer.contains('realme') ||
          manufacturer.contains('oneplus') ||
          manufacturer.contains('xiaomi') ||
          manufacturer.contains('huawei');
    } catch (e) {
      return false;
    }
  }

  /// Check if device is specifically Vivo
  static Future<bool> isVivoDevice() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.manufacturer.toLowerCase().contains('vivo');
    } catch (e) {
      return false;
    }
  }

  /// Get device info for debugging
  static Future<Map<String, String>> getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return {
        'manufacturer': androidInfo.manufacturer,
        'model': androidInfo.model,
        'android': androidInfo.version.release,
        'sdk': androidInfo.version.sdkInt.toString(),
      };
    } catch (e) {
      return {
        'manufacturer': 'unknown',
        'model': 'unknown',
        'android': 'unknown',
        'sdk': 'unknown',
      };
    }
  }

  /// Request all necessary permissions including autostart
  static Future<bool> requestAllPermissions() async {
    try {
      // Request SMS permissions
      final smsStatus = await Permission.sms.request();
      final phoneStatus = await Permission.phone.request();

      if (kDebugMode) {
        print('SMS Permission: $smsStatus');
        print('Phone Permission: $phoneStatus');
      }


      // For Chinese OEMs, request autostart permission
      if (await isChineseOEM()) {

        print('⚠️ Chinese OEM detected - requesting autostart');
        try {
          await servicePlatform.invokeMethod('requestAutoStartPermission');
        } catch (e) {
          print('Could not open autostart settings: $e');
        }
      }

      return smsStatus.isGranted && phoneStatus.isGranted;
    } catch (e) {
      print('Error requesting permissions: $e');
      return false;
    }
  }

  /// Check if we have SMS permission
  static Future<bool> hasSmsPermission() async {
    try {
      final result = await platform.invokeMethod('hasSmsPermission');
      return result == true;
    } catch (e) {
      final smsGranted = await Permission.sms.isGranted;
      final phoneGranted = await Permission.phone.isGranted;
      return smsGranted && phoneGranted;
    }
  }

  /// Send SMS using native method with ENHANCED retry logic for Vivo
  static Future<bool> sendSMS(String phoneNumber, String message) async {
    try {
      // Ensure we have permissions
      if (!await hasSmsPermission()) {
        print('❌ No SMS permission - requesting...');
        await requestAllPermissions();

        // Wait a bit for permissions to be granted
        await Future.delayed(const Duration(milliseconds: 500));

        if (!await hasSmsPermission()) {
          print('❌ SMS permission still not granted');
          return false;
        }
      }

      print('📱 Sending SMS to $phoneNumber');
      print('📝 Message length: ${message.length} characters');

      // For Vivo devices, use enhanced sending with retries
      final isVivo = await isVivoDevice();
      if (isVivo) {
        print('📱 Vivo device detected - using enhanced retry logic');
        return await _sendSMSWithVivoRetry(phoneNumber, message);
      }

      // For other devices, try native method with timeout
      try {
        final result = await platform.invokeMethod('sendSMS', {
          'phoneNumber': phoneNumber,
          'message': message,
        }).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⏱️ SMS send timeout');
            return false;
          },
        );

        if (result == true) {
          print('✅ SMS sent successfully via native method');
          return true;
        }
      } catch (e) {
        print('❌ Native SMS failed: $e');
      }

      // If Chinese OEM, show guidance
      if (await isChineseOEM()) {
        print('💡 On Vivo/OPPO devices:');
        print('   1. Enable "Autostart" for this app');
        print('   2. Allow "Background activity"');
        print('   3. Disable battery optimization');
      }

      return false;

    } catch (e) {
      print('❌ SMS service error: $e');
      return false;
    }
  }

  /// Enhanced retry logic specifically for Vivo devices
  static Future<bool> _sendSMSWithVivoRetry(
      String phoneNumber,
      String message, {
        int maxRetries = 5,
      }) async {
    int successCount = 0;
    int failureCount = 0;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      print('📱 Vivo SMS Attempt $attempt/$maxRetries to $phoneNumber');

      try {
        // Add random delay to avoid rate limiting
        if (attempt > 1) {
          final delayMs = 1000 + (attempt * 500); // Increasing delay
          print('⏳ Waiting ${delayMs}ms before retry...');
          await Future.delayed(Duration(milliseconds: delayMs));
        }

        final result = await platform.invokeMethod('sendSMS', {
          'phoneNumber': phoneNumber,
          'message': message,
        }).timeout(
          Duration(seconds: 5 + (attempt * 2)), // Increasing timeout
          onTimeout: () {
            print('⏱️ Timeout on attempt $attempt');
            return false;
          },
        );

        if (result == true) {
          successCount++;
          print('✅ SMS sent successfully on attempt $attempt');

          // For Vivo, wait a bit to ensure message was actually sent
          await Future.delayed(const Duration(milliseconds: 1500));

          // If we have more than one success, consider it definitely sent
          if (successCount >= 2 || attempt >= maxRetries) {
            print('✅ SMS confirmed sent with $successCount successes');
            return true;
          }
        } else {
          failureCount++;
          print('❌ Failed on attempt $attempt');
        }
      } catch (e) {
        failureCount++;
        print('❌ Error on attempt $attempt: $e');
      }
    }

    // If we had at least one success, consider it sent
    if (successCount > 0) {
      print('⚠️ SMS possibly sent ($successCount successes, $failureCount failures)');
      return true;
    }

    print('❌ Failed to send SMS after $maxRetries attempts');
    return false;
  }

  /// Send emergency SMS with location - ENHANCED for Vivo
  static Future<bool> sendEmergencySMS(String phoneNumber, {required String message}) async {
    try {
      final deviceInfo = await getDeviceInfo();
      print('');
      print('═══════════════════════════════════');
      print('📱 Sending Emergency SMS');
      print('═══════════════════════════════════');
      print('Device: ${deviceInfo['manufacturer']} ${deviceInfo['model']}');
      print('Android: ${deviceInfo['android']} (SDK ${deviceInfo['sdk']})');
      print('To: $phoneNumber');
      print('═══════════════════════════════════');

      // Get location with timeout
      String fullMessage;
      try {
        fullMessage = await LocationService.getFullLocationMessage()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        print('⚠️ Could not get location: $e');
        fullMessage = '🚨 EMERGENCY ALERT 🚨\n'
            'Accident detected! Unable to get location.\n'
            'Please send help immediately!';
      }

      // Check if Vivo device
      final isVivo = await isVivoDevice();
      if (isVivo) {
        print('📱 Vivo device detected - using enhanced sending');
        print('💡 This may take multiple attempts...');
      }

      // Attempt to send SMS with retries
      final success = await sendSMS(phoneNumber, fullMessage);

      if (!success) {
        // Log detailed error for user
        print('');
        print('═══════════════════════════════════');
        print('⚠️  SMS SENDING FAILED');
        print('═══════════════════════════════════');
        print('Possible reasons:');
        print('1. App does not have SMS permission');
        print('2. Autostart is disabled (Vivo/OPPO)');
        print('3. Battery optimization is enabled');
        print('4. Background activity restricted');
        print('5. Network/carrier issue');
        print('═══════════════════════════════════');

        // Show user what to check
        if (isVivo) {
          print('');
          print('📱 Vivo users: Please ensure:');
          print('   ✓ Settings → Apps → Rescue Me → Permissions → SMS (ALLOW)');
          print('   ✓ Settings → Apps → Rescue Me → Autostart (ENABLE)');
          print('   ✓ Settings → Battery → Rescue Me → No restrictions');
          print('   ✓ Settings → Apps → Rescue Me → Background activity (ALLOW)');
          print('');
        }
      } else {
        print('✅ Emergency SMS sent successfully to $phoneNumber');
      }

      return success;

    } catch (e) {
      print('❌ Emergency SMS error: $e');
      return false;
    }
  }

  /// Send SMS to multiple contacts with proper spacing for Vivo
  static Future<int> sendEmergencySMSToContacts(List<String> phoneNumbers) async {
    int successCount = 0;
    final isVivo = await isVivoDevice();

    // Vivo devices need longer delays between messages
    final delayBetweenMessages = isVivo ? 3000 : 1000;

    print('');
    print('═══════════════════════════════════');
    print('📤 Sending to ${phoneNumbers.length} contacts');
    if (isVivo) {
      print('⚠️ Vivo device: Using ${delayBetweenMessages}ms delay between SMS');
    }
    print('═══════════════════════════════════');

    for (int i = 0; i < phoneNumbers.length; i++) {
      final phoneNumber = phoneNumbers[i];
      print('📱 Sending to contact ${i + 1}/${phoneNumbers.length}: $phoneNumber');

      try {
        final success = await sendEmergencySMS(phoneNumber, message: '');
        if (success) {
          successCount++;
          print('✅ Sent to $phoneNumber ($successCount/${i + 1})');
        } else {
          print('❌ Failed to send to $phoneNumber');
        }

        // Add delay between messages (important for Vivo!)
        if (i < phoneNumbers.length - 1) {
          print('⏳ Waiting ${delayBetweenMessages}ms before next message...');
          await Future.delayed(Duration(milliseconds: delayBetweenMessages));
        }
      } catch (e) {
        print('❌ Error sending to $phoneNumber: $e');
      }
    }

    print('');
    print('═══════════════════════════════════');
    print('📊 Results: $successCount/${phoneNumbers.length} sent');
    print('═══════════════════════════════════');
    print('');

    return successCount;
  }

  /// Send quick emergency SMS
  static Future<bool> sendQuickEmergencySMS(String phoneNumber) async {
    try {
      Position? position;
      try {
        position = await LocationService.getCurrentLocation()
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        print('⚠️ Quick location failed: $e');
      }

      String message;
      if (position == null) {
        message = '🚨 EMERGENCY ALERT 🚨\n'
            'Accident detected! Unable to get location.\n'
            'Please send help immediately!';
      } else {
        message = LocationService.getQuickLocationMessage(position);
      }

      return await sendSMS(phoneNumber, message);

    } catch (e) {
      print('❌ Quick emergency SMS error: $e');
      return false;
    }
  }

  /// Test SMS sending (for debugging) - ENHANCED for Vivo
  static Future<bool> testSMS(String phoneNumber) async {
    print('');
    print('═══════════════════════════════════');
    print('🧪 Testing SMS functionality');
    print('═══════════════════════════════════');

    // Check device info
    final deviceInfo = await getDeviceInfo();
    print('📱 Device: ${deviceInfo['manufacturer']} ${deviceInfo['model']}');
    print('📱 Android: ${deviceInfo['android']} (SDK ${deviceInfo['sdk']})');

    // Check permissions
    final smsGranted = await Permission.sms.isGranted;
    final phoneGranted = await Permission.phone.isGranted;
    print('✓ SMS Permission: $smsGranted');
    print('✓ Phone Permission: $phoneGranted');

    // Check if Chinese OEM
    final isOEM = await isChineseOEM();
    final isVivo = await isVivoDevice();
    print('⚠️ Chinese OEM: $isOEM');
    print('⚠️ Vivo Device: $isVivo');

    // Try to send test message
    final message = '🧪 Test message from Rescue Me app at ${DateTime.now().toString().substring(0, 19)}';
    print('📨 Sending test SMS to $phoneNumber...');
    print('═══════════════════════════════════');

    final success = await sendSMS(phoneNumber, message);

    print('═══════════════════════════════════');
    if (success) {
      print('✅ TEST PASSED - SMS sent successfully');
    } else {
      print('❌ TEST FAILED - SMS could not be sent');

      if (isVivo) {
        print('');
        print('💡 Vivo Troubleshooting:');
        print('1. Go to Settings → Apps → Rescue Me');
        print('2. Enable "Autostart"');
        print('3. Enable "Background activity"');
        print('4. Disable "Battery optimization"');
        print('5. Grant all SMS permissions');
      }
    }
    print('═══════════════════════════════════');
    print('');

    return success;
  }

  /// Log detailed diagnostic information
  static Future<void> logDiagnostics() async {
    print('');
    print('═══════════════════════════════════');
    print('🔍 SMS Service Diagnostics');
    print('═══════════════════════════════════');

    final deviceInfo = await getDeviceInfo();
    print('Device: ${deviceInfo['manufacturer']} ${deviceInfo['model']}');
    print('Android: ${deviceInfo['android']} (SDK ${deviceInfo['sdk']})');

    final isOEM = await isChineseOEM();
    final isVivo = await isVivoDevice();
    print('Chinese OEM: $isOEM');
    print('Vivo Device: $isVivo');

    final hasSms = await hasSmsPermission();
    print('SMS Permission: $hasSms');

    final smsGranted = await Permission.sms.isGranted;
    final phoneGranted = await Permission.phone.isGranted;
    final sendSmsGranted = await Permission.sms.isGranted;
    print('SMS: $smsGranted');
    print('Phone: $phoneGranted');
    print('Send SMS: $sendSmsGranted');

    print('═══════════════════════════════════');
    print('');
  }
}