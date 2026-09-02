import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../features/home/models/scan_result.dart';

export '../features/home/models/scan_result.dart';

enum ScanStatus { idle, scanning, paused, done }

/// Manages scan lifecycle: category selection, streaming results, recovery.
/// Lives in Provider tree so any screen can read/write state.
class ScanState extends ChangeNotifier {
  static const _methodChannel = MethodChannel('com.nowdigiverse.recovery/core');
  static const _eventChannel =
      EventChannel('com.nowdigiverse.recovery/scan_stream');

  // Callback when Quick Scan triggered from widget while app is running
  VoidCallback? onQuickScanTriggered;

  ScanState() {
    _methodChannel.setMethodCallHandler((call) async {
      if (call.method == 'triggerQuickScan') {
        onQuickScanTriggered?.call();
      }
    });
  }

  // ── Category selection ─────────────────────────────────────────────────────
  final Set<ScanCategory> _selected = {};
  Set<ScanCategory> get selectedCategories => Set.unmodifiable(_selected);

  void toggleCategory(ScanCategory cat) {
    if (_selected.contains(cat)) {
      _selected.remove(cat);
    } else {
      _selected.add(cat);
    }
    notifyListeners();
  }

  void selectAllCategories() {
    _selected.addAll(ScanCategory.values);
    notifyListeners();
  }

  // ── Scan state ─────────────────────────────────────────────────────────────
  ScanStatus _status = ScanStatus.idle;
  ScanStatus get status => _status;

  final List<ScanResult> _results = [];
  List<ScanResult> get results => List.unmodifiable(_results);

  int get selectedCount => _results.where((r) => r.isSelected).length;
  List<ScanResult> get selectedResults =>
      _results.where((r) => r.isSelected).toList();

  StreamSubscription<dynamic>? _scanSub;

  // ── Recovery state ─────────────────────────────────────────────────────────
  bool _recovering = false;
  bool get recovering => _recovering;

  List<Map<String, dynamic>> _recoveredItems = [];
  List<Map<String, dynamic>> get recoveredItems =>
      List.unmodifiable(_recoveredItems);

  // ── Scan control ───────────────────────────────────────────────────────────

  Future<String?> pickSafFolder() async {
    try {
      final uri = await _methodChannel.invokeMethod<String>('pickSafFolder');
      return uri;
    } catch (e) {
      debugPrint('[ScanState] pickSafFolder error: $e');
      return null;
    }
  }

  Future<void> startScan({String? safUri}) async {
    // Cancel any in-flight scan subscription first.
    await _scanSub?.cancel();
    _scanSub = null;

    _results.clear();
    _status = ScanStatus.scanning;
    notifyListeners();

    final categoryIds = _selected.isEmpty
        ? <String>[]
        : _selected.map((c) => c.id).toList();

    // Subscribe to stream BEFORE calling native startScan so no results are
    // missed between the onListen callback and the scan thread starting.
    _scanSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (data is Map) {
          _results.add(
            ScanResult.fromMap(
              Map<String, dynamic>.from(data),
            ),
          );
          notifyListeners();
        }
      },
      onDone: () {
        _status = ScanStatus.done;
        _scanSub = null;
        notifyListeners();
        debugPrint('[ScanState] Scan done — ${_results.length} results');
      },
      onError: (dynamic e) {
        debugPrint('[ScanState] Scan stream error: $e');
        _status = ScanStatus.done;
        _scanSub = null;
        notifyListeners();
      },
      cancelOnError: true,
    );

    try {
      final Map<String, dynamic> args = {'categories': categoryIds};
      if (safUri != null) args['safUri'] = safUri;
      await _methodChannel.invokeMethod('startScan', args);
    } catch (e) {
      debugPrint('[ScanState] startScan error: $e');
      _status = ScanStatus.done;
      notifyListeners();
    }
  }

  Future<void> startDeepScan() async {
    await _scanSub?.cancel();
    _scanSub = null;

    _results.clear();
    _status = ScanStatus.scanning;
    notifyListeners();

    final categoryIds = _selected.isEmpty
        ? <String>[]
        : _selected.map((c) => c.id).toList();

    _scanSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (data is Map) {
          _results.add(
            ScanResult.fromMap(
              Map<String, dynamic>.from(data),
            ),
          );
          notifyListeners();
        }
      },
      onDone: () {
        _status = ScanStatus.done;
        _scanSub = null;
        notifyListeners();
        debugPrint('[ScanState] Deep scan done — ${_results.length} results');
      },
      onError: (dynamic e) {
        debugPrint('[ScanState] Deep scan stream error: $e');
        _status = ScanStatus.done;
        _scanSub = null;
        notifyListeners();
      },
      cancelOnError: true,
    );

    try {
      await _methodChannel.invokeMethod('startDeepScan', {
        'categories': categoryIds,
      });
    } catch (e) {
      debugPrint('[ScanState] startDeepScan error: $e');
      _status = ScanStatus.done;
      notifyListeners();
    }
  }

  Future<void> pauseScan() async {
    try {
      await _methodChannel.invokeMethod('pauseScan');
    } catch (_) {}
    _status = ScanStatus.paused;
    await _scanSub?.cancel();
    _scanSub = null;
    notifyListeners();
  }

  Future<bool> hasResumeState() async {
    try {
      final hasState = await _methodChannel.invokeMethod<bool>('checkResumeState');
      return hasState ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> resumeDeepScan() async {
    await _scanSub?.cancel();
    _scanSub = null;

    _status = ScanStatus.scanning;
    notifyListeners();

    _scanSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (data is Map) {
          _results.add(
            ScanResult.fromMap(
              Map<String, dynamic>.from(data),
            ),
          );
          notifyListeners();
        }
      },
      onDone: () {
        _status = ScanStatus.done;
        _scanSub = null;
        notifyListeners();
      },
      onError: (dynamic e) {
        _status = ScanStatus.done;
        _scanSub = null;
        notifyListeners();
      },
      cancelOnError: true,
    );

    try {
      await _methodChannel.invokeMethod('resumeDeepScan');
    } catch (e) {
      _status = ScanStatus.done;
      notifyListeners();
    }
  }

  Future<void> clearResumeState() async {
    try {
      await _methodChannel.invokeMethod('clearResumeState');
    } catch (_) {}
  }

  Future<bool> checkQuickScanIntent() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('checkQuickScanIntent');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
  
  Future<Map<String, dynamic>> checkDeviceResources() async {
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>('checkDeviceResources');
      return result ?? {'batteryLevel': 100, 'isCharging': true, 'isHot': false};
    } catch (_) {
      return {'batteryLevel': 100, 'isCharging': true, 'isHot': false};
    }
  }

  Future<int> checkAvailableStorage() async {
    try {
      final result = await _methodChannel.invokeMethod<int>('checkAvailableStorage');
      return result ?? 999999999;
    } catch (_) {
      return 999999999; // Dummy value if fails
    }
  }

  Future<void> cancelScan() async {
    try {
      await _methodChannel.invokeMethod('cancelScan');
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    _status = ScanStatus.done;
    notifyListeners();
  }

  void resetScan() {
    _results.clear();
    _status = ScanStatus.idle;
    _recoveredItems = [];
    notifyListeners();
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  void toggleSelect(ScanResult item) {
    item.isSelected = !item.isSelected;
    notifyListeners();
  }

  void selectAll() {
    for (final r in _results) {
      r.isSelected = true;
    }
    notifyListeners();
  }

  void deselectAll() {
    for (final r in _results) {
      r.isSelected = false;
    }
    notifyListeners();
  }

  // ── Recovery ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> recoverSelected() async {
    if (_recovering) return [];
    _recovering = true;
    notifyListeners();

    try {
      final items = selectedResults
          .map((r) => {
                'uri': r.uri,
                'path': r.path,
                'name': r.name,
                'source': r.source,
              })
          .toList();

      final raw = await _methodChannel.invokeMethod<List<dynamic>>(
        'recoverFiles',
        {'items': items},
      );

      _recoveredItems = (raw ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList();

      debugPrint('[ScanState] Recovered ${_recoveredItems.length} files');
      return _recoveredItems;
    } catch (e) {
      debugPrint('[ScanState] recoverFiles error: $e');
      return [];
    } finally {
      _recovering = false;
      notifyListeners();
    }
  }

  Future<void> openFile(String path) async {
    try {
      await _methodChannel.invokeMethod('openFile', {'path': path});
    } catch (e) {
      debugPrint('[ScanState] openFile error: $e');
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }
}
