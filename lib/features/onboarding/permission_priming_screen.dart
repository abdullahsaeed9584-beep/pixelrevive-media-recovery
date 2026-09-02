import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../shared/theme/app_theme.dart';

/// Permission priming screen — shown before triggering system permission dialogs.
/// Provides clear context for each permission before the system dialog fires.
class PermissionPrimingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const PermissionPrimingScreen({super.key, required this.onDone});

  @override
  State<PermissionPrimingScreen> createState() =>
      _PermissionPrimingScreenState();
}

class _PermissionPrimingScreenState extends State<PermissionPrimingScreen> {
  bool _requesting = false;
  String? _statusMessage;

  Future<void> _requestPermissions() async {
    setState(() {
      _requesting = true;
      _statusMessage = 'Checking Android version…';
    });

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    setState(() => _statusMessage = 'Requesting storage access…');

    // --- Storage permission (branched by API level) ---
    if (sdkInt >= 30) {
      // Android 11+: MANAGE_EXTERNAL_STORAGE
      final status = await Permission.manageExternalStorage.request();
      debugPrint('[Permissions] MANAGE_EXTERNAL_STORAGE → $status');
    } else {
      // Legacy READ + WRITE_EXTERNAL_STORAGE
      final statuses = await [
        Permission.storage,
      ].request();
      debugPrint('[Permissions] storage → ${statuses[Permission.storage]}');
    }

    // --- Notification permission (Android 13+ / API 33+) ---
    if (sdkInt >= 33) {
      setState(() => _statusMessage = 'Requesting notification access…');
      final notifStatus = await Permission.notification.request();
      debugPrint('[Permissions] notification → $notifStatus');
    }

    setState(() {
      _requesting = false;
      _statusMessage = null;
    });

    // Proceed regardless of permission outcome — app handles denial gracefully
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 48),

              // Header icon
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.security_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),

              SizedBox(height: 36),

              Text(
                'Before We Begin',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Media Recovery needs two permissions to work. Here\'s why:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),

              SizedBox(height: 40),

              // Permission cards
              _PermissionCard(
                icon: Icons.folder_open_rounded,
                iconColor: Theme.of(context).colorScheme.secondary,
                title: 'Storage Access',
                description:
                    'To scan your device for recoverable files and protect folders you choose. Nothing leaves your device.',
              ),
              SizedBox(height: 14),
              _PermissionCard(
                icon: Icons.notifications_rounded,
                iconColor: AppColors.accentOrange,
                title: 'Notifications',
                description:
                    'To alert you instantly when Protection Mode detects a file is about to be deleted.',
              ),

              Spacer(),

              // Status message during requesting
              if (_statusMessage != null) ...[
                Center(
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFamily: 'Inter',
                      fontSize: 13,
                    ),
                  ),
                ),
                SizedBox(height: 12),
              ],

              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _requesting ? null : _requestPermissions,
                  child: _requesting
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Text('Allow Permissions'),
                ),
              ),
              SizedBox(height: 16),
              TextButton(
                onPressed: _requesting ? null : widget.onDone,
                child: Text(
                  'Maybe later',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'Inter',
                    fontSize: 14,
                  ),
                ),
              ),
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _PermissionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
