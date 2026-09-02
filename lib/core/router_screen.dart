import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/permission_priming_screen.dart';
import '../shared/widgets/main_shell.dart';
import '../core/app_state.dart';
import 'package:provider/provider.dart';

/// Decides which route to show on start:
/// 1. Onboarding (first launch)
/// 2. Permission priming (permissions not yet granted)
/// 3. Main shell (ready to use)
class RouterScreen extends StatefulWidget {
  const RouterScreen({super.key});

  @override
  State<RouterScreen> createState() => _RouterScreenState();
}

class _RouterScreenState extends State<RouterScreen> {
  bool _loading = true;
  bool _showOnboarding = false;
  bool _showPermissions = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;

    if (!mounted) return;
    final appState = context.read<AppState>();
    await appState.initialise();

    if (!mounted) return;
    setState(() {
      _showOnboarding = !onboardingDone;
      _showPermissions = !onboardingDone ? false : !appState.permissionsGranted;
      _loading = false;
    });
  }

  void _onOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    setState(() {
      _showOnboarding = false;
      _showPermissions = true;
    });
  }

  void _onPermissionsDone() {
    context.read<AppState>().setPermissionsGranted(true);
    setState(() {
      _showPermissions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_showOnboarding) {
      return OnboardingScreen(onDone: _onOnboardingDone);
    }
    if (_showPermissions) {
      return PermissionPrimingScreen(onDone: _onPermissionsDone);
    }
    return MainShell();
  }
}
