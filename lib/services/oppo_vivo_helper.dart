import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';

class OppoVivoHelper {
  /// Check if the device is OPPO, Vivo, Realme, or OnePlus
  static Future<bool> isRestrictedDevice() async {
    if (!Platform.isAndroid) return false;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();

      return manufacturer.contains('oppo') ||
          manufacturer.contains('vivo') ||
          manufacturer.contains('realme') ||
          manufacturer.contains('oneplus') ||
          manufacturer.contains('xiaomi') ||
          manufacturer.contains('redmi');
    } catch (e) {
      if (kDebugMode) {
        print('Error checking device: $e');
      }
      return false;
    }
  }

  /// Get device manufacturer name
  static Future<String> getManufacturer() async {
    if (!Platform.isAndroid) return 'Unknown';

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.manufacturer;
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Request battery optimization exemption
  static Future<bool> requestBatteryOptimizationExemption(String packageName) async {
    if (!Platform.isAndroid) return false;

    try {
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:$packageName',
      );
      await intent.launch();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting battery optimization: $e');
      }
      return false;
    }
  }

  /// Open app settings page
  static Future<bool> openAppSettings(String packageName) async {
    if (!Platform.isAndroid) return false;

    try {
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$packageName',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error opening app settings: $e');
      }
      return false;
    }
  }

  /// Try to open auto-start settings (manufacturer-specific)
  static Future<bool> openAutoStartSettings() async {
    if (!Platform.isAndroid) return false;

    final manufacturer = (await getManufacturer()).toLowerCase();

    try {
      AndroidIntent? intent;

      if (manufacturer.contains('xiaomi') || manufacturer.contains('redmi')) {
        intent = const AndroidIntent(
          action: 'action',
          componentName: 'com.miui.securitycenter/.autostart.AutoStartManagementActivity',
        );
      } else if (manufacturer.contains('oppo')) {
        intent = const AndroidIntent(
          action: 'action',
          componentName: 'com.coloros.safecenter/.startupapp.StartupAppListActivity',
        );
      } else if (manufacturer.contains('vivo')) {
        intent = const AndroidIntent(
          action: 'action',
          componentName: 'com.vivo.permissionmanager/.activity.BgStartUpManagerActivity',
        );
      } else if (manufacturer.contains('oneplus')) {
        intent = const AndroidIntent(
          action: 'action',
          componentName: 'com.oneplus.security/.chainlaunch.view.ChainLaunchAppListActivity',
        );
      }

      if (intent != null) {
        await intent.launch();
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Auto-start settings not available: $e');
      }
    }

    // Fallback to general app settings
    return false;
  }

  /// Open battery settings
  static Future<bool> openBatterySettings() async {
    if (!Platform.isAndroid) return false;

    try {
      const intent = AndroidIntent(
        action: 'android.settings.BATTERY_SAVER_SETTINGS',
      );
      await intent.launch();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error opening battery settings: $e');
      }
      return false;
    }
  }

  /// Get instructions specific to manufacturer
  static String getManufacturerSpecificInstructions(String manufacturer) {
    final man = manufacturer.toLowerCase();

    if (man.contains('oppo') || man.contains('realme')) {
      return '''
OPPO/Realme Setup:

1. Long press > Go to app info > 
2. Open battery > select "Don't optimize" or "Run in background"
3. Go to app info  > Permissions > Allow all
4. Enable auto-start for this app
5. Lock app in Recent Apps (tap app card and lock icon)
      ''';
    } else if (man.contains('vivo')) {
      return '''
Vivo Setup:
1. Go to Settings > Battery > Background App Management
2. Find this app and allow "High background battery consumption"
3. Go to Settings > More Settings > Auto-start
4. Enable auto-start for this app
5. Lock app in Recent Apps
      ''';
    } else if (man.contains('xiaomi') || man.contains('redmi')) {
      return '''
Xiaomi/Redmi Setup:
1. Go to Settings > Apps > Manage Apps
2. Find this app > Battery Saver > No restrictions
3. Go to Settings > Apps > Manage Apps
4. Find this app > Autostart > Enable
5. Lock app in Recent Apps
      ''';
    } else if (man.contains('oneplus')) {
      return '''
OnePlus Setup:
1. Go to Settings > Battery > Battery Optimization
2. Find this app and select "Don't optimize"
3. Go to Settings > Apps > Auto-start
4. Enable for this app
      ''';
    } else {
      return '''
General Setup:
1. Disable battery optimization for this app
2. Enable auto-start permission
3. Allow background activity
4. Lock app in Recent Apps
      ''';
    }
  }
}