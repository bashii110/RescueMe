// Lib/services/call_service.Dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CallService {
  static const platform = MethodChannel('com.buxhiisd.msg_bypas/call');

  /// Make an emergency call to a phone number
  static Future<bool> makeEmergencyCall(String phoneNumber) async {
    try {
      if (kDebugMode) {
        print("📞 Attempting to call: $phoneNumber");
      }

      final bool result = await platform.invokeMethod('makeCall', {
        'phoneNumber': phoneNumber,
      });

      if (result) {
        if (kDebugMode) {
          print("✅ Call initiated to $phoneNumber");
        }
      } else {
        if (kDebugMode) {
          print("❌ Failed to initiate call to $phoneNumber");
        }
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        print("❌ Call error: $e");
      }
      return false;
    }
  }

  /// Make calls to multiple numbers sequentially with delay
  static Future<void> makeEmergencyCalls(List<String> phoneNumbers, {
    Duration delayBetweenCalls = const Duration(seconds: 3),
  }) async {
    if (phoneNumbers.isEmpty) {
      if (kDebugMode) {
        print("⚠️ No phone numbers provided for calling");
      }
      return;
    }

    if (kDebugMode) {
      print("📞 Starting emergency calls to ${phoneNumbers.length} contacts");
    }

    for (int i = 0; i < phoneNumbers.length; i++) {
      final phoneNumber = phoneNumbers[i];

      if (kDebugMode) {
        print("📞 Calling contact ${i + 1}/${phoneNumbers.length}: $phoneNumber");
      }

      final success = await makeEmergencyCall(phoneNumber);

      if (success) {
        if (kDebugMode) {
          print("✅ Call ${i + 1} successful");
        }

        // Wait before next call (except for last one)
        if (i < phoneNumbers.length - 1) {
          if (kDebugMode) {
            print("⏳ Waiting ${delayBetweenCalls.inSeconds} seconds before next call...");
          }
          await Future.delayed(delayBetweenCalls);
        }
      } else {
        if (kDebugMode) {
          print("❌ Call ${i + 1} failed");
        }
      }
    }

    if (kDebugMode) {
      print("✅ Emergency calling completed");
    }
  }

  /// Check if phone call permission is granted
  static Future<bool> hasCallPermission() async {
    try {
      final bool result = await platform.invokeMethod('hasCallPermission');
      return result;
    } catch (e) {
      if (kDebugMode) {
        print("❌ Permission check error: $e");
      }
      return false;
    }
  }

  /// Request phone call permission
  static Future<bool> requestCallPermission() async {
    try {
      final bool result = await platform.invokeMethod('requestCallPermission');
      return result;
    } catch (e) {
      if (kDebugMode) {
        print("❌ Permission request error: $e");
      }
      return false;
    }
  }
}