import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:msg_bypas/screens/main_screen.dart';
import 'package:msg_bypas/screens/setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..forward();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _checkSetup();
  }

  Future<void> _checkSetup() async {
    await Future.delayed(const Duration(seconds: 3));
    final prefs = await SharedPreferences.getInstance();
    final isSetup = prefs.getBool('is_setup') ?? false;

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
          isSetup ? const MainScreen() : const SetupScreen(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.bgDark, Color(0xFF0D1B2A), AppTheme.bgDark],
          ),
        ),
        child: Stack(
          children: [
            // Background rings
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (_, __) => Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.accent.withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (_, __) => Transform.scale(
                  scale: 1.1 - (_pulseAnimation.value - 0.95) * 0.5,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.accent.withOpacity(0.15),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Main content
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (_, __) => Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [AppTheme.accent, AppTheme.accentDark],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accent.withOpacity(0.4),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.emergency_share_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'RESCUE ME',
                        style: AppTheme.displayFont.copyWith(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: AppTheme.accent.withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'SAFETY GUARDIAN',
                          style: AppTheme.bodyFont.copyWith(
                            fontSize: 11,
                            color: AppTheme.accent,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 60),
                      // Loading dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          return AnimatedBuilder(
                            animation: _pulseController,
                            builder: (_, __) {
                              final delay = i * 0.3;
                              final value = ((_pulseController.value + delay) % 1.0);
                              final opacity = value < 0.5
                                  ? value * 2
                                  : (1.0 - value) * 2;
                              return Container(
                                margin:
                                const EdgeInsets.symmetric(horizontal: 4),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.accent
                                      .withOpacity(0.3 + opacity * 0.7),
                                ),
                              );
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// GLOBAL THEME
// ─────────────────────────────────────────
class AppTheme {
  static const Color bgDark = Color(0xFF0A0F1E);
  static const Color bgCard = Color(0xFF111827);
  static const Color bgCardLight = Color(0xFF1A2235);
  static const Color accent = Color(0xFFE53935);
  static const Color accentDark = Color(0xFFB71C1C);
  static const Color accentGlow = Color(0xFFFF5252);
  static const Color success = Color(0xFF00C853);
  static const Color warning = Color(0xFFFFAB00);
  static const Color textPrimary = Color(0xFFECEFF1);
  static const Color textSecondary = Color(0xFF78909C);
  static const Color border = Color(0xFF1E2D40);

  static const TextStyle displayFont = TextStyle(
    fontFamily: 'Rajdhani',
    color: textPrimary,
  );

  static const TextStyle bodyFont = TextStyle(
    fontFamily: 'Nunito',
    color: textSecondary,
  );

  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgDark,
    primaryColor: accent,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      surface: bgCard,
      background: bgDark,
      error: accentGlow,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: textPrimary),
      titleTextStyle: TextStyle(
        fontFamily: 'Rajdhani',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: 2,
      ),
    ),
    cardTheme: CardTheme(
      color: bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding:
        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: bgCard,
      selectedItemColor: accent,
      unselectedItemColor: textSecondary,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    useMaterial3: false,
  );
}