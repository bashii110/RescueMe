import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/permission_service.dart';
import '../services/oppo_vivo_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, bool> _permissions = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _checkAndShowDeviceSetup();
  }

  Future<void> _checkAndShowDeviceSetup() async {
    // Wait a bit for UI to load
    await Future.delayed(const Duration(milliseconds: 500));

    final isRestricted = await OppoVivoHelper.isRestrictedDevice();
    if (isRestricted && mounted) {
      final prefs = await SharedPreferences.getInstance();
      final hasShownGuide = prefs.getBool('device_setup_guide_shown') ?? false;

      if (!hasShownGuide) {
        final manufacturer = await OppoVivoHelper.getManufacturer();
        _showRestrictedDeviceDialog(manufacturer);
        await prefs.setBool('device_setup_guide_shown', true);
      }
    }
  }

  Future<void> _checkPermissions() async {
    final permissions = await PermissionService.checkAllPermissions();
    setState(() => _permissions = permissions);
  }

  void _showRestrictedDeviceDialog(String manufacturer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${manufacturer.toUpperCase()} Setup Guide'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'For this life-saving app to work properly, you MUST complete these steps:\n',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                OppoVivoHelper.getManufacturerSpecificInstructions(manufacturer),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Without these settings, emergency SMS may not be sent!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();

              // Try to open auto-start settings first
              bool opened = await OppoVivoHelper.openAutoStartSettings();

              if (!opened) {
                // Fallback to app settings
                const packageName = 'com.buxhiisd.msg_bypas';
                await OppoVivoHelper.openAppSettings(packageName);
              }
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rescue Me'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPermissionsSection(),
            const SizedBox(height: 24),
            _buildAboutSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'Permissions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPermissionTile(
              'SMS',
              'Required to send emergency messages',
              _permissions['sms'] ?? false,
              Icons.sms,
            ),
            _buildPermissionTile(
              'Location',
              'Required to share your location',
              _permissions['location'] ?? false,
              Icons.location_on,
            ),
            _buildPermissionTile(
              'Background Location',
              'Required for automatic alerts',
              _permissions['locationAlways'] ?? false,
              Icons.my_location,
            ),
            _buildPermissionTile(
              'Phone',
              'Required to access phone state and make calls',
              _permissions['phone'] ?? false,
              Icons.phone,
            ),
            _buildPermissionTile(
              'Notifications',
              'Required for app alerts',
              _permissions['notification'] ?? false,
              Icons.notifications,
            ),
            _buildPermissionTile(
              'Microphone',
              'Required for noise detection',
              _permissions['microphone'] ?? false,
              Icons.mic,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await PermissionService.requestAllPermissions();
                  _checkPermissions();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Request Permissions'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile(String title, String subtitle, bool granted, IconData icon) {
    return ListTile(
      leading: Icon(
        icon,
        color: granted ? Colors.green : Colors.grey,
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Icon(
        granted ? Icons.check_circle : Icons.cancel,
        color: granted ? Colors.green : Colors.red,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
    );
  }

  Widget _buildAboutSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'About',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Rescue Me - Emergency Alert App',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Version 1.0.0'),
            const SizedBox(height: 16),
            const Text(
              'This app automatically detects accidents using device sensors and sends emergency alerts with your location to your emergency contacts. So please keep your location on during travel.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Important: For OPPO, Vivo, Xiaomi, and similar devices, ensure this app has "Auto-start" permission and is not battery optimized.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Device-specific setup button
            FutureBuilder<bool>(
              future: OppoVivoHelper.isRestrictedDevice(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.data == true) {
                  return Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final manufacturer = await OppoVivoHelper.getManufacturer();
                          _showRestrictedDeviceDialog(manufacturer);
                        },
                        icon: const Icon(Icons.settings_suggest),
                        label: const Text('Device Setup Guide'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          const packageName = 'com.buxhiisd.msg_bypas';
                          await OppoVivoHelper.requestBatteryOptimizationExemption(packageName);
                        },
                        icon: const Icon(Icons.battery_charging_full),
                        label: const Text('Disable Battery Optimization'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}