import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'splash_screen.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────────
  late AnimationController _shieldController;   // shield scale-in
  late AnimationController _ringController;     // expanding rings
  late AnimationController _checkController;    // check draw
  late AnimationController _cardsController;    // staggered cards
  late AnimationController _particleController; // floating particles
  late AnimationController _glowController;     // ambient glow pulse

  // ── Animations ────────────────────────────────────────────
  late Animation<double> _shieldScale;
  late Animation<double> _shieldOpacity;
  late Animation<double> _checkProgress;
  late Animation<double> _glowPulse;

  int _contactCount = 0;
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _loadContactCount();
    _generateParticles();
    _setupAnimations();
    _runSequence();
  }

  void _generateParticles() {
    final rng = Random();
    for (int i = 0; i < 18; i++) {
      _particles.add(_Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 2.0 + rng.nextDouble() * 3,
        speed: 0.3 + rng.nextDouble() * 0.7,
        angle: rng.nextDouble() * 2 * pi,
        opacity: 0.2 + rng.nextDouble() * 0.5,
      ));
    }
  }

  void _setupAnimations() {
    _shieldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cardsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _shieldScale = CurvedAnimation(
      parent: _shieldController,
      curve: Curves.elasticOut,
    );
    _shieldOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _shieldController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _checkProgress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.easeOutCubic),
    );
    _glowPulse = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _shieldController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _ringController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _checkController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _cardsController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.mediumImpact();
  }

  Future<void> _loadContactCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final contacts = prefs.getStringList('emergency_contacts') ?? [];
    if (mounted) setState(() => _contactCount = contacts.length);
  }

  @override
  void dispose() {
    _shieldController.dispose();
    _ringController.dispose();
    _checkController.dispose();
    _cardsController.dispose();
    _particleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(
        children: [
          // ── Background gradient ──────────────────────────
          _buildBackground(size),

          // ── Floating particles ──────────────────────────
          _buildParticles(size),

          // ── Main content ────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        _buildHeroSection(),
                        const SizedBox(height: 32),
                        _buildStatusBadge(),
                        const SizedBox(height: 32),
                        _buildInfoCards(),
                        const SizedBox(height: 32),
                        _buildReturnButton(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Background ─────────────────────────────────────────────
  Widget _buildBackground(Size size) {
    return AnimatedBuilder(
      animation: _glowPulse,
      builder: (_, __) => Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.2,
            colors: [
              AppTheme.success.withValues(alpha: 0.07 * _glowPulse.value),
              AppTheme.bgDark,
              const Color(0xFF050A10),
            ],
          ),
        ),
      ),
    );
  }

  // ── Particles ──────────────────────────────────────────────
  Widget _buildParticles(Size size) {
    return AnimatedBuilder(
      animation: _particleController,
      builder: (_, __) {
        return CustomPaint(
          size: size,
          painter: _ParticlePainter(
            particles: _particles,
            progress: _particleController.value,
            color: AppTheme.success,
          ),
        );
      },
    );
  }

  // ── Top bar ────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                Navigator.of(context).popUntil((r) => r.isFirst),
            icon: const Icon(Icons.close_rounded,
                color: AppTheme.textSecondary, size: 22),
          ),
          const Spacer(),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppTheme.success.withValues(alpha: 0.3)),
              color: AppTheme.success.withValues(alpha: 0.06),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 6),
                Text('ALERT DISPATCHED',
                    style: AppTheme.displayFont.copyWith(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: AppTheme.success,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Hero section ───────────────────────────────────────────
  Widget _buildHeroSection() {
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding rings
          AnimatedBuilder(
            animation: _ringController,
            builder: (_, __) {
              return CustomPaint(
                size: const Size(220, 220),
                painter: _RingsPainter(
                  progress: _ringController.value,
                  color: AppTheme.success,
                ),
              );
            },
          ),

          // Shield with check
          AnimatedBuilder(
            animation: Listenable.merge(
                [_shieldScale, _shieldOpacity, _checkProgress, _glowPulse]),
            builder: (_, __) {
              return Opacity(
                opacity: _shieldOpacity.value,
                child: Transform.scale(
                  scale: _shieldScale.value,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer glow
                      Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.success
                                  .withValues(alpha: 0.25 * _glowPulse.value),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),
                      // Shield body
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.success.withValues(alpha: 0.2),
                              AppTheme.success.withValues(alpha: 0.08),
                            ],
                          ),
                          border: Border.all(
                            color: AppTheme.success.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                      ),
                      // Animated check
                      CustomPaint(
                        size: const Size(48, 48),
                        painter: _CheckPainter(
                          progress: _checkProgress.value,
                          color: AppTheme.success,
                          strokeWidth: 4.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Status badge ───────────────────────────────────────────
  Widget _buildStatusBadge() {
    return AnimatedBuilder(
      animation: _cardsController,
      builder: (_, __) {
        final t = Curves.easeOutCubic
            .transform(_cardsController.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t)),
            child: Column(
              children: [
                Text(
                  'ALERTS SENT',
                  style: AppTheme.displayFont.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'SUCCESSFULLY',
                  style: AppTheme.displayFont.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _contactCount > 0
                      ? 'Emergency SMS sent to $_contactCount contact${_contactCount > 1 ? 's' : ''}'
                      : 'Emergency alerts dispatched',
                  style: AppTheme.bodyFont.copyWith(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Info cards ─────────────────────────────────────────────
  Widget _buildInfoCards() {
    final cards = [
      _CardData(
        icon: Icons.sms_rounded,
        title: 'SMS Delivered',
        subtitle: 'With live GPS coordinates',
        color: AppTheme.success,
        delay: 0.0,
      ),
      _CardData(
        icon: Icons.location_on_rounded,
        title: 'Location Shared',
        subtitle: 'High-accuracy GPS position',
        color: const Color(0xFF42A5F5),
        delay: 0.15,
      ),
      _CardData(
        icon: Icons.map_rounded,
        title: 'Maps Link Included',
        subtitle: 'Google Maps navigation link',
        color: AppTheme.warning,
        delay: 0.3,
      ),
      _CardData(
        icon: Icons.call_rounded,
        title: 'Calls Initiated',
        subtitle: 'Emergency contacts dialled',
        color: const Color(0xFFAB47BC),
        delay: 0.45,
      ),
    ];

    return AnimatedBuilder(
      animation: _cardsController,
      builder: (_, __) {
        return Column(
          children: cards.map((card) {
            final start = card.delay;
            final end = (card.delay + 0.55).clamp(0.0, 1.0);
            final t = Curves.easeOutCubic.transform(
              ((_cardsController.value - start) / (end - start))
                  .clamp(0.0, 1.0),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(30 * (1 - t), 0),
                  child: _buildInfoCard(card),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildInfoCard(_CardData card) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: card.color.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: card.color.withValues(alpha: 0.1),
              border:
              Border.all(color: card.color.withValues(alpha: 0.2)),
            ),
            child: Icon(card.icon, color: card.color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.title,
                    style: AppTheme.displayFont.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(card.subtitle,
                    style: AppTheme.bodyFont.copyWith(fontSize: 12)),
              ],
            ),
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: card.color.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.check_rounded, color: card.color, size: 14),
          ),
        ],
      ),
    );
  }

  // ── Return button ──────────────────────────────────────────
  Widget _buildReturnButton() {
    return AnimatedBuilder(
      animation: _cardsController,
      builder: (_, __) {
        final t = Curves.easeOutCubic.transform(
          ((_cardsController.value - 0.6) / 0.4).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t)),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: AnimatedBuilder(
                animation: _glowPulse,
                builder: (_, __) => Container(
                  width: double.infinity,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF00C853),
                        Color(0xFF00897B),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.success.withValues(alpha:
                            0.25 + _glowPulse.value * 0.15),
                        blurRadius: 20 + _glowPulse.value * 8,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shield_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text('RETURN TO SAFETY SCREEN',
                          style: AppTheme.displayFont.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Data classes ───────────────────────────────────────────────
class _CardData {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final double delay;
  _CardData(
      {required this.icon,
        required this.title,
        required this.subtitle,
        required this.color,
        required this.delay});
}

class _Particle {
  final double x, y, size, speed, angle, opacity;
  _Particle(
      {required this.x,
        required this.y,
        required this.size,
        required this.speed,
        required this.angle,
        required this.opacity});
}

// ── Custom Painters ────────────────────────────────────────────

/// Draws the animated expanding rings on success
class _RingsPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingsPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final delay = i * 0.28;
      final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final eased = Curves.easeOut.transform(t);
      final radius = maxR * 0.4 + (maxR * 0.6) * eased;
      final opacity = (1.0 - eased) * 0.4;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius, paint);
    }

    // Static subtle ring
    final staticPaint = Paint()
      ..color = color.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, maxR * 0.95, staticPaint);
    canvas.drawCircle(center, maxR * 0.65, staticPaint);
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.progress != progress;
}

/// Draws an animated check mark
class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  _CheckPainter(
      {required this.progress,
        required this.color,
        required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Check path: start bottom-left, up to mid, then to top-right
    final p1 = Offset(w * 0.15, h * 0.52);
    final p2 = Offset(w * 0.42, h * 0.75);
    final p3 = Offset(w * 0.85, h * 0.28);

    final totalLength =
        (p2 - p1).distance + (p3 - p2).distance;
    final drawn = totalLength * progress;

    final path = Path();
    path.moveTo(p1.dx, p1.dy);

    final seg1 = (p2 - p1).distance;
    if (drawn <= seg1) {
      final t = drawn / seg1;
      path.lineTo(
          p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final remaining = drawn - seg1;
      final seg2 = (p3 - p2).distance;
      final t = (remaining / seg2).clamp(0.0, 1.0);
      path.lineTo(
          p2.dx + (p3.dx - p2.dx) * t, p2.dy + (p3.dy - p2.dy) * t);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

/// Floating ambient particles
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color color;
  _ParticlePainter(
      {required this.particles,
        required this.progress,
        required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (progress * p.speed + p.x) % 1.0;
      final x = (p.x + cos(p.angle) * t * 0.15) % 1.0 * size.width;
      final y = (p.y - t * 0.12) % 1.0 * size.height;
      final fadeOpacity =
          p.opacity * (1 - (t > 0.7 ? (t - 0.7) / 0.3 : 0));

      final paint = Paint()
        ..color = color.withValues(alpha: fadeOpacity * 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), p.size / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.progress != progress;
}