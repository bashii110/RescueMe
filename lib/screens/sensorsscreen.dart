import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:msg_bypas/screens/splash_screen.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:noise_meter/noise_meter.dart';

// // ─── App Theme (matches HomeScreen) ─────────────────
// class AppTheme {
//   static const Color bgDark        = Color(0xFF0A0A0F);
//   static const Color bgCard        = Color(0xFF12121A);
//   static const Color bgCardLight   = Color(0xFF1A1A26);
//   static const Color accent        = Color(0xFFFF3B5C);
//   static const Color success       = Color(0xFF00E676);
//   static const Color warning       = Color(0xFFFFAB00);
//   static const Color border        = Color(0xFF1E1E2E);
//   static const Color textPrimary   = Color(0xFFEEEEFF);
//   static const Color textSecondary = Color(0xFF6E6E8A);
//
//   static const TextStyle displayFont = TextStyle(
//     fontFamily: 'Courier',
//     color: textPrimary,
//   );
//   static const TextStyle bodyFont = TextStyle(color: textSecondary);
// }

// ─── Sensor Readings Screen ──────────────────────────
// Sensors stream events many times per second. Instead of rebuilding the UI
// on every single event (which used to make the numbers flicker by the
// millisecond), readings are now sampled continuously in the background and
// the screen only refreshes once every 30 seconds. Each refresh also reports
// the highest and lowest peak that each sensor reached during that window.
class SensorReadingsScreen extends StatefulWidget {
  const SensorReadingsScreen({super.key});

  @override
  State<SensorReadingsScreen> createState() => _SensorReadingsScreenState();
}

class _SensorReadingsScreenState extends State<SensorReadingsScreen>
    with SingleTickerProviderStateMixin {
  static const Duration kWindowDuration = Duration(seconds: 2);

  // ── Snapshot values shown on screen — only refreshed every 30s ──
  double _accelX = 0, _accelY = 0, _accelZ = 0;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;
  double _noiseDb = 0, _noiseMaxDb = 0;

  // ── Highest / lowest peak reached by each sensor in the last window ──
  double _accelMagHigh = 0, _accelMagLow = 0;
  double _gyroMagHigh = 0, _gyroMagLow = 0;
  double _noiseHigh = 0, _noiseLow = 0;

  DateTime _windowUpdatedAt = DateTime.now();
  int _secondsUntilNextUpdate = kWindowDuration.inSeconds;

  // ── Raw running values updated on every sensor event (no setState) ──
  double _rawAccelX = 0, _rawAccelY = 0, _rawAccelZ = 0;
  double _rawGyroX = 0, _rawGyroY = 0, _rawGyroZ = 0;
  double _rawNoiseDb = 0, _rawNoiseMaxDb = 0;

  // ── Peak trackers accumulated during the current 30s window ──
  double? _windowAccelHigh;
  double? _windowAccelLow;
  double? _windowGyroHigh;
  double? _windowGyroLow;
  double? _windowNoiseHigh;
  double? _windowNoiseLow;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<NoiseReading>? _noiseSub;
  late NoiseMeter _noiseMeter;

  Timer? _windowTimer;
  Timer? _countdownTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _noiseMeter = NoiseMeter();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _accelSub = accelerometerEventStream().listen((e) {
      _rawAccelX = e.x;
      _rawAccelY = e.y;
      _rawAccelZ = e.z;
      final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _windowAccelHigh =
      (_windowAccelHigh == null) ? mag : max(_windowAccelHigh!, mag);
      _windowAccelLow =
      (_windowAccelLow == null) ? mag : min(_windowAccelLow!, mag);
    });

    _gyroSub = gyroscopeEventStream().listen((e) {
      _rawGyroX = e.x;
      _rawGyroY = e.y;
      _rawGyroZ = e.z;
      final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _windowGyroHigh =
      (_windowGyroHigh == null) ? mag : max(_windowGyroHigh!, mag);
      _windowGyroLow =
      (_windowGyroLow == null) ? mag : min(_windowGyroLow!, mag);
    });

    try {
      _noiseSub = _noiseMeter.noise.listen((r) {
        _rawNoiseDb = r.meanDecibel;
        _rawNoiseMaxDb = r.maxDecibel;
        _windowNoiseHigh = (_windowNoiseHigh == null)
            ? r.meanDecibel
            : max(_windowNoiseHigh!, r.meanDecibel);
        _windowNoiseLow = (_windowNoiseLow == null)
            ? r.meanDecibel
            : min(_windowNoiseLow!, r.meanDecibel);
      });
    } catch (_) {}

    // Refresh the on-screen numbers every 30 seconds instead of on every
    // raw sensor event.
    _windowTimer = Timer.periodic(kWindowDuration, (_) => _commitWindowSnapshot());

    // Lightweight 1-second ticker purely for the "next update in" countdown
    // shown to the user — it does not touch any sensor values.
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsUntilNextUpdate =
            kWindowDuration.inSeconds -
                (DateTime.now().difference(_windowUpdatedAt).inSeconds %
                    kWindowDuration.inSeconds);
      });
    });
  }

  void _commitWindowSnapshot() {
    if (!mounted) return;
    setState(() {
      _accelX = _rawAccelX;
      _accelY = _rawAccelY;
      _accelZ = _rawAccelZ;
      _gyroX = _rawGyroX;
      _gyroY = _rawGyroY;
      _gyroZ = _rawGyroZ;
      _noiseDb = _rawNoiseDb;
      _noiseMaxDb = _rawNoiseMaxDb;

      _accelMagHigh = _windowAccelHigh ?? _accelMag;
      _accelMagLow = _windowAccelLow ?? _accelMag;
      _gyroMagHigh = _windowGyroHigh ?? _gyroMag;
      _gyroMagLow = _windowGyroLow ?? _gyroMag;
      _noiseHigh = _windowNoiseHigh ?? _noiseDb;
      _noiseLow = _windowNoiseLow ?? _noiseDb;

      _windowUpdatedAt = DateTime.now();
      _secondsUntilNextUpdate = kWindowDuration.inSeconds;
    });

    // Reset peak trackers so the next 30-second window starts fresh.
    _windowAccelHigh = null;
    _windowAccelLow = null;
    _windowGyroHigh = null;
    _windowGyroLow = null;
    _windowNoiseHigh = null;
    _windowNoiseLow = null;
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _noiseSub?.cancel();
    _windowTimer?.cancel();
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _ts(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  double get _accelMag =>
      sqrt(_accelX * _accelX + _accelY * _accelY + _accelZ * _accelZ);
  double get _gyroMag =>
      sqrt(_gyroX * _gyroX + _gyroY * _gyroY + _gyroZ * _gyroZ);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('SENSOR',
                style: AppTheme.displayFont.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: Colors.white,
                )),
            const SizedBox(width: 6),
            Text('30s', style: AppTheme.displayFont.copyWith(
              fontSize: 16, fontWeight: FontWeight.w700,
              letterSpacing: 3, color: AppTheme.accent,
            )),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.border),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 10),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLiveIndicator(),
              const SizedBox(height: 20),
              _buildSensorCard(
                label: 'ACCELEROMETER',
                icon: Icons.vibration,
                color: AppTheme.accent,
                x: _accelX, y: _accelY, z: _accelZ,
                magnitude: _accelMag,
                unit: 'm/s²',
                timestamp: _windowUpdatedAt,
                highThreshold: 20.0,
                peakHigh: _accelMagHigh,
                peakLow: _accelMagLow,
              ),
              const SizedBox(height: 12),
              _buildSensorCard(
                label: 'GYROSCOPE',
                icon: Icons.rotate_90_degrees_ccw_rounded,
                color: AppTheme.success,
                x: _gyroX, y: _gyroY, z: _gyroZ,
                magnitude: _gyroMag,
                unit: 'rad/s',
                timestamp: _windowUpdatedAt,
                highThreshold: 3.0,
                peakHigh: _gyroMagHigh,
                peakLow: _gyroMagLow,
              ),
              const SizedBox(height: 12),
              _buildNoiseCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveIndicator() {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) => Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success
                  .withValues(alpha: 0.4 + _pulseController.value * 0.6),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.success.withValues(alpha: 0.4),
                  blurRadius: 6 + _pulseController.value * 4,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('UPDATES EVERY 30s',
          style: AppTheme.displayFont.copyWith(
            fontSize: 11, fontWeight: FontWeight.w700,
            letterSpacing: 2, color: AppTheme.success,
          ),
        ),
        const Spacer(),
        Text('NEXT IN ${_secondsUntilNextUpdate}s',
          style: AppTheme.displayFont.copyWith(
            fontSize: 11, fontWeight: FontWeight.w600,
            letterSpacing: 1, color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSensorCard({
    required String label,
    required IconData icon,
    required Color color,
    required double x, required double y, required double z,
    required double magnitude,
    required String unit,
    required DateTime timestamp,
    required double highThreshold,
    required double peakHigh,
    required double peakLow,
  }) {
    final isHigh = magnitude > highThreshold;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHigh ? color.withValues(alpha: 0.5) : AppTheme.border,
          width: isHigh ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 10),
              Text(label, style: AppTheme.displayFont.copyWith(
                fontSize: 12, fontWeight: FontWeight.w700,
                letterSpacing: 2, color: color,
              )),
              const Spacer(),
              Text(_ts(timestamp), style: AppTheme.displayFont.copyWith(
                fontSize: 10, color: AppTheme.textSecondary,
              )),
            ],
          ),
          const SizedBox(height: 16),
          // X Y Z boxes
          Row(
            children: [
              Expanded(child: _axisBox('X', x, color)),
              const SizedBox(width: 8),
              Expanded(child: _axisBox('Y', y, color)),
              const SizedBox(width: 8),
              Expanded(child: _axisBox('Z', z, color)),
            ],
          ),
          const SizedBox(height: 12),
          // Magnitude
          Row(
            children: [
              Text('MAGNITUDE', style: AppTheme.displayFont.copyWith(
                fontSize: 9, letterSpacing: 2,
                color: AppTheme.textSecondary,
              )),
              const Spacer(),
              Text('${magnitude.toStringAsFixed(3)} $unit',
                style: AppTheme.displayFont.copyWith(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: isHigh ? color : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (magnitude / (highThreshold * 1.5)).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppTheme.bgCardLight,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 14),
          Text('30s PEAK RANGE', style: AppTheme.displayFont.copyWith(
            fontSize: 9, letterSpacing: 2,
            color: AppTheme.textSecondary,
          )),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _peakBox('HIGHEST', peakHigh, unit,
                    peakHigh > highThreshold ? color : AppTheme.textPrimary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _peakBox('LOWEST', peakLow, unit, AppTheme.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _axisBox(String axis, double val, Color color) {
    final highlight = val.abs() > 5;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? color.withValues(alpha: 0.08) : AppTheme.bgCardLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? color.withValues(alpha: 0.25) : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Text(axis, style: AppTheme.displayFont.copyWith(
            fontSize: 10, letterSpacing: 2,
            color: AppTheme.textSecondary,
          )),
          const SizedBox(height: 4),
          Text(
            val >= 0
                ? '+${val.toStringAsFixed(2)}'
                : val.toStringAsFixed(2),
            style: AppTheme.displayFont.copyWith(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: highlight ? color : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _peakBox(String label, double val, String unit, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCardLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: AppTheme.displayFont.copyWith(
            fontSize: 10, letterSpacing: 2,
            color: AppTheme.textSecondary,
          )),
          const SizedBox(height: 4),
          Text('${val.toStringAsFixed(3)} $unit',
            style: AppTheme.displayFont.copyWith(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoiseCard() {
    final isHigh = _noiseDb > 75;
    final color = isHigh ? AppTheme.accent : AppTheme.warning;
    final barVal = (_noiseDb / 120.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHigh ? AppTheme.accent.withValues(alpha: 0.5) : AppTheme.border,
          width: isHigh ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.mic_rounded, size: 15, color: color),
              ),
              const SizedBox(width: 10),
              Text('NOISE LEVEL', style: AppTheme.displayFont.copyWith(
                fontSize: 12, fontWeight: FontWeight.w700,
                letterSpacing: 2, color: color,
              )),
              const Spacer(),
              Text(_ts(_windowUpdatedAt), style: AppTheme.displayFont.copyWith(
                fontSize: 10, color: AppTheme.textSecondary,
              )),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _noiseBox('AVG', _noiseDb, color)),
              const SizedBox(width: 8),
              Expanded(child: _noiseBox('MAX', _noiseMaxDb,
                  _noiseMaxDb > 75 ? AppTheme.accent : AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('LEVEL', style: AppTheme.displayFont.copyWith(
                fontSize: 9, letterSpacing: 2,
                color: AppTheme.textSecondary,
              )),
              const Spacer(),
              Text('${_noiseDb.toStringAsFixed(1)} dB',
                style: AppTheme.displayFont.copyWith(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: isHigh ? AppTheme.accent : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: barVal,
              minHeight: 4,
              backgroundColor: AppTheme.bgCardLight,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 14),
          Text('30s PEAK RANGE', style: AppTheme.displayFont.copyWith(
            fontSize: 9, letterSpacing: 2,
            color: AppTheme.textSecondary,
          )),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _peakBox('HIGHEST', _noiseHigh, 'dB',
                    _noiseHigh > 75 ? AppTheme.accent : AppTheme.textPrimary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _peakBox('LOWEST', _noiseLow, 'dB', AppTheme.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noiseBox(String label, double val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCardLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: AppTheme.displayFont.copyWith(
            fontSize: 10, letterSpacing: 2,
            color: AppTheme.textSecondary,
          )),
          const SizedBox(height: 4),
          Text('${val.toStringAsFixed(1)} dB',
            style: AppTheme.displayFont.copyWith(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}