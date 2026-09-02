import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

/// Global app state managed via Provider.
/// Tracks root status, Android API level, and first-launch flag.
class AppState extends ChangeNotifier {
  static const _channel = MethodChannel('com.nowdigiverse.recovery/core');

  bool _isRooted = false;
  int _apiLevel = 0;
  bool _permissionsGranted = false;
  ThemeMode _themeMode = ThemeMode.system;

  bool get isRooted => _isRooted;
  int get apiLevel => _apiLevel;
  bool get permissionsGranted => _permissionsGranted;
  ThemeMode get themeMode => _themeMode;

  /// Call on app start to populate root and API level from native side.
  Future<void> initialise() async {
    final prefs = await SharedPreferences.getInstance();
    final tmStr = prefs.getString('theme_mode') ?? 'system';
    if (tmStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (tmStr == 'dark') {
      _themeMode = ThemeMode.dark;
    }

    try {
      final bool rooted = await _channel.invokeMethod('checkRootAccess');
      _isRooted = rooted;
      debugPrint('[AppState] checkRootAccess → $rooted');
    } catch (e) {
      debugPrint('[AppState] checkRootAccess error: $e');
      _isRooted = false;
    }

    try {
      final int api = await _channel.invokeMethod('getAndroidApiLevel');
      _apiLevel = api;
      debugPrint('[AppState] getAndroidApiLevel → $api');
      
      // Check if permissions are already granted to skip priming screen
      if (_apiLevel >= 30) {
        _permissionsGranted = await Permission.manageExternalStorage.isGranted;
      } else {
        _permissionsGranted = await Permission.storage.isGranted;
      }
    } catch (e) {
      debugPrint('[AppState] getAndroidApiLevel error: $e');
      _apiLevel = 0;
    }

    notifyListeners();
  }

  void setPermissionsGranted(bool value) {
    _permissionsGranted = value;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
    notifyListeners();
  }
}
