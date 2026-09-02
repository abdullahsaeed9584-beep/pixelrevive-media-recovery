import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/protection_state.dart';
import '../../features/home/home_screen.dart';
import '../../features/protection/protection_screen.dart';
import '../../features/vault/vault_screen.dart';
import '../../features/settings/settings_screen.dart';

/// Bottom-nav shell that hosts the 4 main sections of the app.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final _screens = [
    HomeScreen(),
    ProtectionScreen(),
    VaultScreen(),
    SettingsScreen(),
  ];

  static const _navItems = [
    BottomNavigationBarItem(
      icon: Icon(Icons.search_rounded),
      activeIcon: Icon(Icons.search_rounded),
      label: 'Scan',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.shield_outlined),
      activeIcon: Icon(Icons.shield_rounded),
      label: 'Protection',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.lock_outline_rounded),
      activeIcon: Icon(Icons.lock_rounded),
      label: 'Vault',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.settings_outlined),
      activeIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      context.read<ProtectionState>().lockVault();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHighest, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) {
            final state = context.read<ProtectionState>();
            if (_selectedIndex == 2 && i != 2) {
              // Bug 2: Lock Vault when navigating away from it
              state.lockVault();
            } else if (i == 2) {
              // Bug 1: Refresh Vault when navigating to it
              if (state.isVaultUnlocked) {
                state.loadVaultFiles();
              }
            }
            setState(() => _selectedIndex = i);
          },
          items: _navItems,
        ),
      ),
    );
  }
}
