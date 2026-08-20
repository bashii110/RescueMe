import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';

class PermissionService {
  static final Telephony telephony = Telephony.instance;

  static Future<bool> requestAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.phone,
      Permission.microphone,
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
      Permission.microphone,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    return allGranted;
  }

  static Future<bool> checkSMSPermissions() async {
    return await Permission.sms.isGranted;
  }

  static Future<bool> checkLocationPermissions() async {
    bool location = await Permission.location.isGranted;
    bool locationAlways = await Permission.locationAlways.isGranted;
    return location || locationAlways;
  }

  static Future<bool> requestSMSPermissions() async {
    PermissionStatus status = await Permission.sms.request();
    return status.isGranted;
  }

  static Future<bool> requestLocationPermissions() async {
    PermissionStatus location = await Permission.location.request();
    if (location.isGranted) {
      PermissionStatus locationAlways =
      await Permission.locationAlways.request();
      return locationAlways.isGranted || location.isGranted;
    }
    return false;
  }

  static Future<bool> requestDefaultSMSApp() async {
    try {
      final bool? result = await telephony.requestSmsPermissions;
      return result ?? false;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting SMS permissions: $e');
      }
      return false;
    }
  }

  static Future<bool> isDefaultSMSApp() async {
    try {
      final bool? result = await telephony.isSmsCapable;
      return result ?? false;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking SMS capability: $e');
      }
      return false;
    }
  }

  static Future<Map<String, bool>> checkAllPermissions() async {
    final results = await Future.wait([
      Permission.sms.isGranted,
      Permission.phone.isGranted,
      Permission.location.isGranted,
      Permission.locationAlways.isGranted,
      Permission.notification.isGranted,
      Permission.microphone.isGranted,
    ]);

    return {
      'sms': results[0],
      'phone': results[1],
      'location': results[2],
      'locationAlways': results[3],
      'notification': results[4],
      'microphone': results[5],
    };
  }

  // FIXED: was calling itself → StackOverflowError crash.
  // Renamed so it correctly calls the permission_handler package function.
  static Future<bool> openSystemAppSettings() async {
    return await openAppSettings(); // this now resolves to the package-level function
  }
}