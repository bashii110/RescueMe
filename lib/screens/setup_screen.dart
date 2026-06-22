import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/permission_service.dart';
import '../services/oppo_vivo_helper.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _isLoading = false;
  bool _isRestrictedDevice = false;
  String _manufacturer = '';

  @override
  void initState() {
    super.initState();
    _checkDevice();
  }

  Future<void> _checkDevice() async {
    final isRestricted = await OppoVivoHelper.isRestrictedDevice();
    final manufacturer = await OppoVivoHelper.getManufacturer();

    setState(() {
      _isRestrictedDevice = isRestricted;
      _manufacturer = manufacturer;
    });
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    try {
      bool granted = await PermissionService.requestAllPermissions();

      if (granted) {
        // If it's a restricted device, show special instructions
        if (_isRestrictedDevice) {
          _showRestrictedDeviceDialog();
        } else {
          // Skip to completion since no contact required
          _completeSetup();
        }
      } else {
        _showErrorDialog('Permissions Required',
            'Please grant all permissions for the app to function properly.');
      }
    } catch (e) {
      _showErrorDialog('Error', 'Failed to request permissions: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showRestrictedDeviceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 8),
            Text('${_manufacturer.toUpperCase()} Device Detected'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'For this life-saving app to work properly on your device, you MUST complete these steps:\n',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(OppoVivoHelper.getManufacturerSpecificInstructions(_manufacturer)),
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
            onPressed: () {
              Navigator.of(ctx).pop();
              _completeSetup();
            },
            child: const Text('I\'ll Do It Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();

              // Try to open auto-start settings first
              bool opened = await OppoVivoHelper.openAutoStartSettings();

              if (!opened) {
                // Fallback to app settings
                const packageName = 'com.buxhiisd.msg_bypas';
                await OppoVivoHelper.openAppSettings(packageName);
              }

              // Complete setup after showing settings
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  _completeSetup();
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Open Settings Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeSetup() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_setup', true);

      // Request battery optimization exemption for restricted devices
      if (_isRestrictedDevice) {
        const packageName = 'com.buxhiisd.msg_bypas';
        await OppoVivoHelper.requestBatteryOptimizationExemption(packageName);
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      _showErrorDialog('Error', 'Failed to complete setup: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Rescue Me'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Show warning banner for restricted devices
          if (_isRestrictedDevice)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_manufacturer.toUpperCase()} device: Additional setup required!',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.emergency,
                      size: 100,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Welcome to Rescue Me',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Automatic accident detection and emergency alerts',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 48),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Required Permissions:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildPermissionTile(
                              Icons.sms,
                              'SMS',
                              'Send emergency messages',
                            ),
                            _buildPermissionTile(
                              Icons.location_on,
                              'Location',
                              'Share your location in emergencies',
                            ),
                            _buildPermissionTile(
                              Icons.phone,
                              'Phone',
                              'Make emergency calls',
                            ),
                            _buildPermissionTile(
                              Icons.mic,
                              'Microphone',
                              'Detect loud noises (accidents)',
                            ),
                            _buildPermissionTile(
                              Icons.notifications,
                              'Notifications',
                              'Alert you of app status',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _requestPermissions,
                        icon: _isLoading
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.check_circle),
                        label: Text(
                          _isLoading ? 'Setting up...' : 'Grant Permissions & Continue',
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        border: Border.all(color: Colors.blue.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'You can add emergency contacts later from the home screen.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTile(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}