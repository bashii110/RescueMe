import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/sms_service.dart';
import '../services/call_service.dart';
import '../services/contacts_notifier.dart';
import 'splash_screen.dart';
import 'sos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  bool _isMonitoring = false;
  bool _isLoading = false;
  bool _isAccidentDetected = false;
  bool _isAlarmPlaying = false;
  bool _isBatteryOptimized = true;

  double _accelerateX = 0.0, _accelerateY = 0.0, _accelerateZ = 0.0;
  double _gyroscopeX = 0.0, _gyroscopeY = 0.0, _gyroscopeZ = 0.0;
  double _latestDB = 0.0;

  late NoiseMeter _noiseMeter;
  late AudioPlayer _audioPlayer;
  late AnimationController _radarController;
  late AnimationController _pulseController;
  late AnimationController _sosController;

  StreamSubscription<NoiseReading>? _noiseSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  final List<double> _recentAccelerations = [];

  // ─── Detection thresholds ───────────────────────────
  static const double accelThreshold  = 45.0;  // m/s²
  static const double gyroThreshold   = 4.0;   // rad/s
  static const double noiseThreshold  = 82.0;  // dB
  static const int    timeWindow     = 2000;  // 2 seconds
  static const int    smoothWindow           = 5;
  static const int    alarmDuration          = 30;

  // Timestamps — each records when that sensor last crossed its threshold.
  // All three must have fired within DETECTION_WINDOW_MS to confirm accident.
  DateTime? _accelTriggerTime;
  DateTime? _gyroTriggerTime;
  DateTime? _noiseTriggerTime;

  static const platform      = MethodChannel('com.buxhiisd.msg_bypas/alarm');
  static const serviceChannel = MethodChannel('com.buxhiisd.msg_bypas/service');

  DateTime? _countdownEndTime;
  Timer? _uiUpdateTimer;
  Timer? _userSafeCheckTimer;
  int _contactCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noiseMeter  = NoiseMeter();
    _audioPlayer = AudioPlayer();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _sosController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _loadSettings();
    _checkBatteryOptimization();
    _loadContactCount();
    platform.setMethodCallHandler(_handleMethodCall);

    ContactsNotifier.instance.addListener(_loadContactCount);
  }

  Future<void> _loadContactCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final contacts = prefs.getStringList('emergency_contacts') ?? [];
    if (mounted) setState(() => _contactCount = contacts.length);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onAccidentDetectedBackground') {
      if (!_isMonitoring) {
        if (kDebugMode) {
          print('⚠️ Ignored background accident signal — monitoring is off');
        }
        return;
      }
      if (kDebugMode) {
        print('🚨 Accident detected from background service!');
      }
      if (mounted && !_isAccidentDetected) {
        _triggerAccident();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ContactsNotifier.instance.removeListener(_loadContactCount);
    _stopForegroundMonitoring();
    _uiUpdateTimer?.cancel();
    _userSafeCheckTimer?.cancel();
    _audioPlayer.dispose();
    _stopNativeAlarmService();
    _radarController.dispose();
    _pulseController.dispose();
    _sosController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkCountdownStatus();
      _checkUserSafeStatus();
      _loadContactCount();
    }
  }

  void _checkCountdownStatus() {
    if (_countdownEndTime != null) {
      final now = DateTime.now();
      if (now.isAfter(_countdownEndTime!)) _onCountdownComplete();
    }
  }

  Future<void> _checkUserSafeStatus() async {
    try {
      final result = await platform.invokeMethod('checkUserSafe');
      if (result == true) _handleUserSafe();
    } catch (_) {}
  }

  Future<void> _checkBatteryOptimization() async {
    try {
      final result = await serviceChannel.invokeMethod('isBatteryOptimized');
      setState(() => _isBatteryOptimized = result == true);
    } catch (_) {}
  }

  Future<void> _requestIgnoreBatteryOptimization() async {
    try {
      await serviceChannel.invokeMethod('requestIgnoreBatteryOptimization');
      await Future.delayed(const Duration(seconds: 2));
      await _checkBatteryOptimization();
    } catch (_) {}
  }

  int _getRemainingSeconds() {
    if (_countdownEndTime == null) return alarmDuration;
    final remaining = _countdownEndTime!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isMonitoring = prefs.getBool('monitoring_enabled') ?? false);
    if (_isMonitoring) {
      _startBackgroundService();
      _startForegroundMonitoring();
      _radarController.repeat();
    }
  }

  Future<void> _startBackgroundService() async {
    try {
      await serviceChannel.invokeMethod('startMonitoringService');
    } catch (_) {}
  }

  Future<void> _stopBackgroundService() async {
    try {
      await serviceChannel.invokeMethod('stopMonitoringService');
    } catch (_) {}
  }

  void _startForegroundMonitoring() {
    if (!_isMonitoring) return;
    try {
      _noiseSubscription = _noiseMeter.noise.listen((reading) {
        if (mounted) {
          _latestDB = reading.meanDecibel;
          if (!_isAlarmPlaying) _checkForAccident();
        }
      });
    } catch (_) {}

    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      _accelerateX = event.x;
      _accelerateY = event.y;
      _accelerateZ = event.z;
      if (!_isAlarmPlaying) _checkForAccident();
    });

    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      _gyroscopeX = event.x;
      _gyroscopeY = event.y;
      _gyroscopeZ = event.z;
    });
  }

  void _stopForegroundMonitoring() {
    _noiseSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    // Clear any partial trigger state so stale timestamps
    // don't carry over into the next monitoring session.
    _resetTriggerTimestamps();
  }

  // ─── Core detection logic ────────────────────────────────────────────────
  // Each sensor independently records the last time it crossed its threshold.
  // An accident is confirmed only when ALL THREE timestamps exist AND the
  // spread between the oldest and newest is within DETECTION_WINDOW_MS.
  // Any timestamp older than the window is expired and cleared automatically,
  // so a partial match from a previous non-accident event can never combine
  // with a later unrelated event to produce a false trigger.
  //
  void _checkForAccident() {
    if (_isAccidentDetected || !_isMonitoring) return;

    final double accelMag = sqrt(
        _accelerateX * _accelerateX +
            _accelerateY * _accelerateY +
            _accelerateZ * _accelerateZ);

    final double gyroMag = sqrt(
        _gyroscopeX * _gyroscopeX +
            _gyroscopeY * _gyroscopeY +
            _gyroscopeZ * _gyroscopeZ);

    // Smoothing window for accelerometer
    _recentAccelerations.add(accelMag);
    if (_recentAccelerations.length > smoothWindow) {
      _recentAccelerations.removeAt(0);
    }
    if (_recentAccelerations.isEmpty) return;

    final double avgAccel = _recentAccelerations.reduce((a, b) => a + b) /
        _recentAccelerations.length;

    final now = DateTime.now();

    // ── Step 1: Expire timestamps that are outside the detection window.
    //    This ensures a partial trigger from 5 seconds ago doesn't combine
    //    with a fresh spike today.
    if (_accelTriggerTime != null &&
        now.difference(_accelTriggerTime!).inMilliseconds > timeWindow) {
      _accelTriggerTime = null;
    }
    if (_gyroTriggerTime != null &&
        now.difference(_gyroTriggerTime!).inMilliseconds > timeWindow) {
      _gyroTriggerTime = null;
    }
    if (_noiseTriggerTime != null &&
        now.difference(_noiseTriggerTime!).inMilliseconds > timeWindow) {
      _noiseTriggerTime = null;
    }

    // ── Step 2: Record a fresh timestamp if the sensor crosses its threshold.
    if (avgAccel  > accelThreshold)  _accelTriggerTime = now;
    if (gyroMag   > gyroThreshold)   _gyroTriggerTime  = now;
    if (_latestDB > noiseThreshold)  _noiseTriggerTime = now;

    // ── Step 3: All three must have triggered to proceed.
    if (_accelTriggerTime == null ||
        _gyroTriggerTime  == null ||
        _noiseTriggerTime == null) {
      return;
    }

    // ── Step 4: Check that all three fall within the detection window.
    //    Find the oldest and newest timestamps — the spread must be ≤ 2 s.
    final List<DateTime> times = [
      _accelTriggerTime!,
      _gyroTriggerTime!,
      _noiseTriggerTime!,
    ];
    final DateTime oldest = times.reduce((a, b) => a.isBefore(b) ? a : b);
    final DateTime newest = times.reduce((a, b) => a.isAfter(b)  ? a : b);
    final int spreadMs = newest.difference(oldest).inMilliseconds;

    if (spreadMs <= timeWindow) {
      // ✅ Accident confirmed — all 3 sensors fired within the window.
      _resetTriggerTimestamps();
      _triggerAccident();
    }
    // If spreadMs > DETECTION_WINDOW_MS the oldest timestamp would already
    // have been expired in Step 1 on a future call, so no explicit reset needed.
  }

  void _resetTriggerTimestamps() {
    _accelTriggerTime = null;
    _gyroTriggerTime  = null;
    _noiseTriggerTime = null;
  }

  void _triggerAccident() {
    _isAccidentDetected = true;
    _recentAccelerations.clear();
    _resetTriggerTimestamps(); // belt-and-suspenders
    _startAccidentCountdown();
  }

  Future<void> _startAccidentCountdown() async {
    _countdownEndTime = DateTime.now().add(const Duration(seconds: alarmDuration));
    await _startAlarm();
    try {
      await platform.invokeMethod('turnScreenOn');
    } catch (_) {}
    try {
      await platform.invokeMethod('startAlarmService', {'duration': alarmDuration});
    } catch (_) {}
    _startUserSafePolling();
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final remaining = _getRemainingSeconds();
      if (mounted) setState(() {});
      if (remaining <= 0) {
        timer.cancel();
        _onCountdownComplete();
      }
    });
    if (mounted) _showAccidentDialog();
  }

  void _startUserSafePolling() {
    _userSafeCheckTimer?.cancel();
    _userSafeCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isAccidentDetected) {
        timer.cancel();
        return;
      }
      _checkUserSafeStatus();
    });
  }

  Future<void> _onCountdownComplete() async {
    if (!_isAccidentDetected) return;
    _uiUpdateTimer?.cancel();
    _userSafeCheckTimer?.cancel();
    _countdownEndTime = null;
    await _stopAlarm();
    await _stopNativeAlarmService();
    await _sendEmergencySMS();
    if (mounted) {
      if (Navigator.canPop(context)) Navigator.of(context).pop();
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const SosScreen()));
      setState(() => _isAccidentDetected = false);
    }
  }

  void _handleUserSafe() {
    _uiUpdateTimer?.cancel();
    _userSafeCheckTimer?.cancel();
    _countdownEndTime = null;
    _stopAlarm();
    _stopNativeAlarmService();
    if (mounted) {
      if (Navigator.canPop(context)) Navigator.of(context).pop();
      setState(() => _isAccidentDetected = false);
      _showSnackBar('✅ Alarm cancelled — Stay safe!', AppTheme.success);
    }
  }

  Future<void> _stopNativeAlarmService() async {
    try {
      await platform.invokeMethod('stopAlarmService');
    } catch (_) {}
  }

  Future<void> _startAlarm() async {
    _isAlarmPlaying = true;
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setAudioContext(const AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
      await _audioPlayer.play(AssetSource('images/Alert_alarm.wav'));
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  Future<void> _stopAlarm() async {
    _isAlarmPlaying = false;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  void _showAccidentDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: _AccidentAlertDialog(
          getRemainingSeconds: _getRemainingSeconds,
          onSafe: () {
            _handleUserSafe();
          },
          onSendNow: () async {
            _uiUpdateTimer?.cancel();
            _userSafeCheckTimer?.cancel();
            _countdownEndTime = null;
            await _stopNativeAlarmService();
            await _stopAlarm();
            Navigator.of(dialogContext).pop();
            await _sendEmergencySMS();
            Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SosScreen()));
            setState(() => _isAccidentDetected = false);
          },
        ),
      ),
    );
  }

  Future<void> _sendEmergencySMS() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson = prefs.getStringList('emergency_contacts') ?? [];
      if (contactsJson.isEmpty) return;
      List<String> phoneNumbers = [];
      for (String contactJson in contactsJson) {
        final parts = contactJson.split('|');
        if (parts.length >= 2) {
          await SMSService.sendEmergencySMS(parts[1], message: '');
          phoneNumbers.add(parts[1]);
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      if (phoneNumbers.isNotEmpty) {
        final hasPermission = await CallService.hasCallPermission();
        if (!hasPermission) {
          await CallService.requestCallPermission();
          await Future.delayed(const Duration(seconds: 2));
        }
        await CallService.makeEmergencyCalls(phoneNumbers,
            delayBetweenCalls: const Duration(seconds: 30));
      }
    } catch (_) {}
  }

  Future<void> _toggleMonitoring() async {
    setState(() => _isMonitoring = !_isMonitoring);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('monitoring_enabled', _isMonitoring);
    if (_isMonitoring) {
      await _startBackgroundService();
      _startForegroundMonitoring();
      _radarController.repeat();
      _showSnackBar('Shield activated — Monitoring started', AppTheme.success);
    } else {
      await _stopBackgroundService();
      _stopForegroundMonitoring();
      _radarController.stop();
      _radarController.reset();
      _showSnackBar('Shield deactivated', AppTheme.warning);
    }
  }

  Future<void> _sendManualAlert() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ConfirmSosDialog(
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await _sendEmergencySMS();
        setState(() => _isLoading = false);
        if (!mounted) return;
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SosScreen()));
      } catch (e) {
        _showSnackBar('Error: $e', AppTheme.accent);
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: AppTheme.bodyFont
              .copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isBatteryOptimized) ...[
                    _buildBatteryWarning(),
                    const SizedBox(height: 16),
                  ],
                  _buildRadarCard(),
                  const SizedBox(height: 16),
                  _buildStatsRow(),
                  const SizedBox(height: 16),
                  _buildHowItWorksCard(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildSosFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 80,
      floating: true,
      pinned: true,
      backgroundColor: AppTheme.bgDark,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding:
        const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppTheme.accent, AppTheme.accentDark],
                ),
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.4),
                      blurRadius: 8)
                ],
              ),
              child: const Icon(Icons.emergency_share_rounded,
                  size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text('RESCUE ME',
                style: AppTheme.displayFont.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 3)),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.border),
      ),
    );
  }

  Widget _buildRadarCard() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.bgCard,
            _isMonitoring
                ? AppTheme.accent.withValues(alpha: 0.08)
                : AppTheme.bgCard,
          ],
        ),
        border: Border.all(
          color: _isMonitoring
              ? AppTheme.accent.withValues(alpha: 0.3)
              : AppTheme.border,
          width: 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isMonitoring)
            AnimatedBuilder(
              animation: _radarController,
              builder: (_, __) {
                return CustomPaint(
                  size: const Size(280, 280),
                  painter: _RadarPainter(_radarController.value),
                );
              },
            ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _toggleMonitoring,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) {
                    final scale = _isMonitoring
                        ? 0.97 + _pulseController.value * 0.06
                        : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _isMonitoring
                                ? [AppTheme.accent, AppTheme.accentDark]
                                : [AppTheme.bgCardLight, AppTheme.bgCard],
                          ),
                          boxShadow: _isMonitoring
                              ? [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.5),
                              blurRadius: 30,
                              spreadRadius: 5,
                            )
                          ]
                              : [],
                          border: Border.all(
                            color: _isMonitoring
                                ? AppTheme.accent
                                : AppTheme.border,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isMonitoring
                                  ? Icons.sensors
                                  : Icons.sensors_off,
                              size: 36,
                              color: _isMonitoring
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isMonitoring ? 'ACTIVE' : 'TAP',
                              style: AppTheme.displayFont.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: _isMonitoring
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isMonitoring ? 'SHIELD ACTIVE' : 'SHIELD INACTIVE',
                style: AppTheme.displayFont.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: _isMonitoring
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isMonitoring
                    ? 'Background monitoring running'
                    : 'Tap the button to start',
                style: AppTheme.bodyFont.copyWith(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _toggleMonitoring,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: _isMonitoring
                          ? AppTheme.accent.withValues(alpha: 0.5)
                          : AppTheme.border,
                    ),
                    color: _isMonitoring
                        ? AppTheme.accent.withValues(alpha: 0.12)
                        : AppTheme.bgCardLight,
                  ),
                  child: Text(
                    _isMonitoring ? 'STOP MONITORING' : 'START MONITORING',
                    style: AppTheme.displayFont.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: _isMonitoring
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            Icons.contacts_rounded,
            '$_contactCount',
            'Contacts',
            AppTheme.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            Icons.sensors,
            _isMonitoring ? 'ON' : 'OFF',
            'Sensor',
            _isMonitoring ? AppTheme.accent : AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            Icons.location_on_rounded,
            'GPS',
            'Location',
            AppTheme.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: AppTheme.displayFont.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color)),
          Text(label,
              style: AppTheme.bodyFont
                  .copyWith(fontSize: 10, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard() {
    final items = [
      ['Monitors sensors for sudden impacts', Icons.sensors],
      ['Works in background when app is closed', Icons.phone_android],
      ['Works when screen is off', Icons.screen_lock_portrait],
      ['Sends SMS with live GPS location', Icons.sms],
      ['Calls emergency contacts automatically', Icons.call],
      ['Includes Google Maps navigation link', Icons.map],
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text('HOW IT WORKS',
                style: AppTheme.displayFont.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: AppTheme.textPrimary)),
          ]),
          const SizedBox(height: 16),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(item[1] as IconData,
                      size: 14, color: AppTheme.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item[0] as String,
                      style: AppTheme.bodyFont.copyWith(
                          fontSize: 13,
                          color: AppTheme.textSecondary)
                  ),
                ),
              ],
            ),
          )
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.directions_car_rounded,
                    color: AppTheme.warning, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'For best detection, keep your phone mounted or placed on the seat — not in your pocket.',
                    style: AppTheme.bodyFont.copyWith(
                        fontSize: 12, color: AppTheme.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.warning.withValues(alpha: 0.08),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.battery_alert_rounded,
              color: AppTheme.warning, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Battery Optimization Active',
                    style: AppTheme.displayFont.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warning)),
                const SizedBox(height: 2),
                Text('Disable for reliable background detection',
                    style: AppTheme.bodyFont.copyWith(fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _requestIgnoreBatteryOptimization,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.warning,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('FIX',
                  style: AppTheme.displayFont.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosFab() {
    return AnimatedBuilder(
      animation: _sosController,
      builder: (_, __) {
        return GestureDetector(
          onTap: _isLoading ? null : _sendManualAlert,
          child: Container(
            height: 60,
            width: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                colors: [AppTheme.accent, AppTheme.accentDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent
                      .withValues(alpha: 0.3 + _sosController.value * 0.2),
                  blurRadius: 15 + _sosController.value * 8,
                  spreadRadius: 1 + _sosController.value * 2,
                ),
              ],
            ),
            child: _isLoading
                ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.emergency_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('SEND SOS',
                    style: AppTheme.displayFont.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        color: Colors.white)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Radar Painter ───────────────────────────────────
class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center    = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 1; i <= 4; i++) {
      final paint = Paint()
        ..color      = AppTheme.accent.withValues(alpha: 0.06)
        ..style      = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, maxRadius * (i / 4), paint);
    }

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          AppTheme.accent.withValues(alpha: 0.0),
          AppTheme.accent.withValues(alpha: 0.25),
          Colors.transparent,
        ],
        stops: const [0.0, 0.7, 0.9, 1.0],
        startAngle: 0,
        endAngle: 2 * pi,
        transform: GradientRotation(progress * 2 * pi),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius, sweepPaint);

    final linePaint = Paint()
      ..color       = AppTheme.accent.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    final angle = progress * 2 * pi - pi / 2;
    canvas.drawLine(
      center,
      Offset(center.dx + maxRadius * cos(angle),
          center.dy + maxRadius * sin(angle)),
      linePaint,
    );

    final blipAngle  = (progress * 2 * pi * 0.7) - pi / 2;
    final blipRadius = maxRadius * 0.55;
    final blipPaint  = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(center.dx + blipRadius * cos(blipAngle),
          center.dy + blipRadius * sin(blipAngle)),
      3,
      blipPaint,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─── Accident Alert Dialog ───────────────────────────
class _AccidentAlertDialog extends StatefulWidget {
  final int Function() getRemainingSeconds;
  final VoidCallback onSafe;
  final VoidCallback onSendNow;
  const _AccidentAlertDialog(
      {required this.getRemainingSeconds,
        required this.onSafe,
        required this.onSendNow});

  @override
  State<_AccidentAlertDialog> createState() => _AccidentAlertDialogState();
}

class _AccidentAlertDialogState extends State<_AccidentAlertDialog>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  late AnimationController _flashController;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _timer = Timer.periodic(
        const Duration(milliseconds: 200), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.getRemainingSeconds();
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: 5)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _flashController,
              builder: (_, __) => Text('⚠ ACCIDENT DETECTED',
                  style: AppTheme.displayFont.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: Color.lerp(AppTheme.accent, AppTheme.accentGlow,
                        _flashController.value),
                  )),
            ),
            const SizedBox(height: 6),
            Text('Emergency contacts will be notified',
                style: AppTheme.bodyFont.copyWith(fontSize: 12)),
            const SizedBox(height: 24),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.3), width: 2),
                color: AppTheme.accent.withValues(alpha: 0.08),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$remaining',
                      style: AppTheme.displayFont.copyWith(
                          fontSize: 52,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accent)),
                  Text('SECONDS',
                      style: AppTheme.displayFont.copyWith(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: widget.onSafe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text("I'M SAFE",
                    style: AppTheme.displayFont.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: widget.onSendNow,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.accent),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('SEND SOS NOW',
                    style: AppTheme.displayFont.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: AppTheme.accent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Confirm SOS Dialog ──────────────────────────────
class _ConfirmSosDialog extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const _ConfirmSosDialog(
      {required this.onConfirm, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.1),
                border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Icon(Icons.emergency_rounded,
                  color: AppTheme.accent, size: 28),
            ),
            const SizedBox(height: 16),
            Text('SEND EMERGENCY ALERT?',
                style: AppTheme.displayFont.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Text(
                'This will send emergency SMS with your live GPS location to all contacts.',
                textAlign: TextAlign.center,
                style: AppTheme.bodyFont.copyWith(fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('CANCEL',
                        style: AppTheme.displayFont.copyWith(
                            fontSize: 13,
                            letterSpacing: 1,
                            color: AppTheme.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('SEND',
                        style: AppTheme.displayFont.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}