import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[Workmanager] Executing background task: $taskName');
    
    if (taskName == 'autoVaultBackup') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final folders = prefs.getStringList('monitored_folders') ?? [];
        if (folders.isEmpty) return Future.value(true);

        const methodChannel = MethodChannel('com.nowdigiverse.recovery/core');
        await methodChannel.invokeMethod('sweepVaultFolders', {'folders': folders});
        return Future.value(true);
      } catch (e) {
        debugPrint('[Workmanager] Sweep error: $e');
        return Future.value(false);
      }
    }
    
    return Future.value(true);
  });
}

class BackgroundTaskManager {
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  static Future<void> setAutoBackupFrequency(String frequency) async {
    await Workmanager().cancelAll();
    
    if (frequency == 'Daily') {
      await Workmanager().registerPeriodicTask(
        'vaultBackupDaily',
        'autoVaultBackup',
        frequency: Duration(days: 1),
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: true,
        ),
      );
    } else if (frequency == 'Weekly') {
      await Workmanager().registerPeriodicTask(
        'vaultBackupWeekly',
        'autoVaultBackup',
        frequency: Duration(days: 7),
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: true,
        ),
      );
    }
  }
}
