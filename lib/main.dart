// lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────
// Entry point for ResQ — an offline-first disaster relief assistant.
//
// Architecture overview:
//   • AppState (ChangeNotifier) is injected at the root via Provider.
//   • The SplashScreen initialises all services before showing the main UI.
//   • Bottom navigation routes to: Chat | Map | Checklist | Guide
//   • Gemma 4 E2B runs fully on-device via LiteRT (.tflite in assets/model/).
//   • No internet connection is required for any feature.
//
// Prize tracks: Global Resilience | Digital Equity | Cactus | LiteRT

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'services/app_state.dart';
import 'screens/chat_screen.dart';
import 'screens/map_screen.dart';
import 'screens/checklist_screen.dart';
import 'screens/guide_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise tile caching backend (ObjectBox) for fully offline maps.
  // Wrapped in try/catch so a corrupted FMTC store doesn't kill the app.
  try {
    await FMTCObjectBoxBackend().initialise();
    final store = FMTCStore('jaipur');
    try {
      await store.manage.create();
    } catch (_) {}
  } catch (e) {
    debugPrint('[FMTC] Backend init failed (non-fatal): $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const ResQApp(),
    ),
  );
}

// ── Root app widget ───────────────────────────────────────────────────────────

class ResQApp extends StatelessWidget {
  const ResQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResQ',
      debugShowCheckedModeBanner: false,
      // ── Theme ────────────────────────────────────────────────────────────
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system, // Respects device dark-mode setting
      home: const _SplashGate(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    // Emergency colour palette: deep red primary, orange secondary
    const seedColor = Color(0xFFCC2200); // Deep emergency red

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      secondary: const Color(0xFFE65100), // Deep orange for secondary actions
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? const Color(0xFF1A1A1A)
            : Colors.white,
        indicatorColor: colorScheme.primary.withOpacity(0.15),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardTheme(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

// ── Splash / Init gate ────────────────────────────────────────────────────────

/// Shows a branded loading screen while AppState initialises all services.
/// Transitions automatically to the main shell once ready.
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  @override
  void initState() {
    super.initState();
    // Kick off all service initialisation after the first frame so that
    // the Provider tree is fully wired before we start notifying listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;

    // ── Navigate away once init is done ─────────────────────────────────────
    if (state.isInitialised) {
      // Use a post-frame callback to avoid calling Navigator during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => state.hasCompletedOnboarding
                ? const MainShell()
                : const OnboardingScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      });
    }

    // ── Splash screen ────────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.9),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                      color: colorScheme.primary.withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5),
                ],
              ),
              child: const Icon(
                Icons.health_and_safety_rounded,
                size: 64,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'ResQ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'When networks fail, ResQ stands.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 60),
            // Loading indicator
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                  color: Colors.redAccent, strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text(
              state.initStatus,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Main Shell with bottom navigation ─────────────────────────────────────────

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  static const _screens = [
    ChatScreen(),
    MapScreen(),
    ChecklistScreen(),
    GuideScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: IndexedStack(
        // IndexedStack keeps all screens alive so state isn't lost when
        // switching tabs — important for ongoing AI responses.
        index: state.activeTab,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.activeTab,
        onDestinationSelected: (i) => state.switchTab(i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: state.t('nav_chat'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map_rounded),
            label: state.t('nav_map'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.checklist_outlined),
            selectedIcon: const Icon(Icons.checklist_rounded),
            label: state.t('nav_checklist'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.medical_services_outlined),
            selectedIcon: const Icon(Icons.medical_services_rounded),
            label: state.t('nav_guide'),
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
