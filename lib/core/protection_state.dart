import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProtectionState extends ChangeNotifier {
  static const _channel = MethodChannel('com.nowdigiverse.recovery/core');
  final LocalAuthentication _auth = LocalAuthentication();

  bool _isProtectionEnabled = false;
  bool get isProtectionEnabled => _isProtectionEnabled;

  List<String> _monitoredFolders = [];
  List<String> get monitoredFolders => List.unmodifiable(_monitoredFolders);

  bool _hasPin = false;
  bool get hasPin => _hasPin;

  bool _isVaultUnlocked = false;
  bool get isVaultUnlocked => _isVaultUnlocked;

  int _failedAttempts = 0;
  DateTime? _lockoutEndTime;
  bool get isLockedOut => _lockoutEndTime != null && DateTime.now().isBefore(_lockoutEndTime!);
  Duration get remainingLockout => isLockedOut ? _lockoutEndTime!.difference(DateTime.now()) : Duration.zero;

  List<Map<String, dynamic>> _vaultFiles = [];
  List<Map<String, dynamic>> get vaultFiles => List.unmodifiable(_vaultFiles);

  ProtectionState() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _isProtectionEnabled = prefs.getBool('protection_enabled') ?? false;
    _monitoredFolders = prefs.getStringList('monitored_folders') ?? [];
    
    try {
      _hasPin = await _channel.invokeMethod<bool>('hasVaultPin') ?? false;
    } catch (_) {}

    notifyListeners();

    if (_isProtectionEnabled) {
      await _startService();
    }
  }

  Future<void> _startService() async {
    try {
      await _channel.invokeMethod('startProtection', {'folders': _monitoredFolders});
    } catch (e) {
      debugPrint('Failed to start protection service: $e');
    }
  }

  Future<void> _stopService() async {
    try {
      await _channel.invokeMethod('stopProtection');
    } catch (e) {
      debugPrint('Failed to stop protection service: $e');
    }
  }

  Future<void> toggleProtection(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    _isProtectionEnabled = enable;
    await prefs.setBool('protection_enabled', enable);
    notifyListeners();

    if (enable) {
      await _startService();
    } else {
      await _stopService();
    }
  }

  Future<void> updateFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    _monitoredFolders = List.from(folders);
    await prefs.setStringList('monitored_folders', _monitoredFolders);
    notifyListeners();

    if (_isProtectionEnabled) {
      await _startService(); // Restart with new folders
    }
  }

  Future<bool> setPin(String pin) async {
    try {
      final success = await _channel.invokeMethod<bool>('setVaultPin', {'pin': pin}) ?? false;
      if (success) {
        _hasPin = true;
        notifyListeners();
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyPin(String pin) async {
    if (isLockedOut) return false;

    try {
      final success = await _channel.invokeMethod<bool>('checkVaultPin', {'pin': pin}) ?? false;
      if (success) {
        _isVaultUnlocked = true;
        _failedAttempts = 0;
        notifyListeners();
      } else {
        _failedAttempts++;
        if (_failedAttempts >= 5) {
          _lockoutEndTime = DateTime.now().add(Duration(seconds: 30));
          // Reset attempts so they can try again after lockout
          _failedAttempts = 0; 
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyBiometric() async {
    if (isLockedOut) return false;

    try {
      final canAuth = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canAuth) return false;

      final success = await _auth.authenticate(
        localizedReason: 'Unlock Vault',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (success) {
        _isVaultUnlocked = true;
        _failedAttempts = 0;
        notifyListeners();
      } else {
        _failedAttempts++;
        if (_failedAttempts >= 5) {
          _lockoutEndTime = DateTime.now().add(Duration(seconds: 30));
          _failedAttempts = 0; 
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  void lockVault() {
    _isVaultUnlocked = false;
    _vaultFiles = [];
    notifyListeners();
  }

  Future<void> loadVaultFiles() async {
    debugPrint('loadVaultFiles called. _isVaultUnlocked: $_isVaultUnlocked');
    if (!_isVaultUnlocked) return;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getVaultFiles');
      debugPrint('getVaultFiles returned: ${raw?.length} items. Type: ${raw.runtimeType}');
      if (raw != null) {
        _vaultFiles = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // Sort newest first
        _vaultFiles.sort((a, b) => (b['dateProtected'] as int).compareTo(a['dateProtected'] as int));
        debugPrint('Processed vault files successfully. _vaultFiles.length = ${_vaultFiles.length}');
        notifyListeners();
      }
    } catch (e, stacktrace) {
      debugPrint('Failed to load vault files: $e\n$stacktrace');
    }
  }

  Future<String?> decryptFile(String encryptedName) async {
    try {
      return await _channel.invokeMethod<String>('decryptVaultFile', {'encryptedName': encryptedName});
    } catch (e) {
      return null;
    }
  }

  Future<String?> decryptFileToCache(String encryptedName, {bool isThumbnail = false}) async {
    try {
      return await _channel.invokeMethod<String>('decryptVaultFileToCache', {
        'encryptedName': encryptedName,
        'isThumbnail': isThumbnail,
      });
    } catch (e) {
      return null;
    }
  }

  Future<bool> deleteFile(String encryptedName) async {
    try {
      final success = await _channel.invokeMethod<bool>('deleteVaultFile', {'encryptedName': encryptedName}) ?? false;
      if (success) {
        _vaultFiles.removeWhere((f) => f['encryptedName'] == encryptedName);
        notifyListeners();
      }
      return success;
    } catch (e) {
      return false;
    }
  }
}
