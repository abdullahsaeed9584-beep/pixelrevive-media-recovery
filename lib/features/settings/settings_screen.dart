import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_state.dart';
import '../../core/background_tasks.dart';
import '../../shared/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widget_guide_screen.dart';

/// Settings tab — shows app info, root/API status, and auto-backup frequency.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _backupFrequency = 'Off';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backupFrequency = prefs.getString('auto_backup_freq') ?? 'Off';
    });
  }

  Future<void> _updateBackupFrequency(String? freq) async {
    if (freq == null || freq == _backupFrequency) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auto_backup_freq', freq);
    setState(() {
      _backupFrequency = freq;
    });

    await BackgroundTaskManager.setAutoBackupFrequency(freq);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Automation
          _SectionHeader('Automation'),
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            ),
            child: Row(
              children: [
                Icon(Icons.autorenew_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                SizedBox(width: 14),
                Text(
                  'Auto-Vault Backup',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Spacer(),
                DropdownButton<String>(
                  value: _backupFrequency,
                  underline: SizedBox(),
                  dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  items: [
                    DropdownMenuItem(value: 'Off', child: Text('Off')),
                    DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                  ],
                  onChanged: _updateBackupFrequency,
                ),
              ],
            ),
          ),

          // Guides
          _SectionHeader('Guides'),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WidgetGuideScreen(),
              ));
            },
            child: _InfoTile(
              icon: Icons.widgets_rounded,
              label: 'Widget Setup Guide',
              value: 'View',
              valueColor: Theme.of(context).colorScheme.primary,
            ),
          ),
          SizedBox(height: 14),

          // Info section
          _SectionHeader('Device Info'),
          _InfoTile(
            icon: Icons.android_rounded,
            label: 'Android API Level',
            value: appState.apiLevel > 0 ? appState.apiLevel.toString() : '—',
          ),
          _InfoTile(
            icon: Icons.admin_panel_settings_rounded,
            label: 'Root Access',
            value: appState.apiLevel == 0
                ? 'Checking…'
                : (appState.isRooted ? 'Granted ✓' : 'Not available'),
            valueColor: appState.isRooted
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          _InfoTile(
            icon: Icons.folder_open_rounded,
            label: 'Storage Permissions',
            value: appState.permissionsGranted ? 'Granted ✓' : 'Not granted',
            valueColor: appState.permissionsGranted
                ? Theme.of(context).colorScheme.primary
                : AppColors.accentOrange,
          ),

          SizedBox(height: 24),
          _SectionHeader('Personalization'),
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            ),
            child: Row(
              children: [
                Icon(Icons.dark_mode_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                SizedBox(width: 14),
                Text(
                  'Theme',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Spacer(),
                DropdownButton<ThemeMode>(
                  value: appState.themeMode,
                  underline: SizedBox(),
                  dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  items: [
                    DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                  ],
                  onChanged: (mode) {
                    if (mode != null) appState.setThemeMode(mode);
                  },
                ),
              ],
            ),
          ),

          _SectionHeader('App'),
          _InfoTile(
            icon: Icons.info_outline_rounded,
            label: 'Version',
            value: '1.0.0 (Phase 6)',
          ),
          _InfoTile(
            icon: Icons.lock_outline_rounded,
            label: 'Privacy Policy',
            value: 'No data leaves your device',
          ),
          SizedBox(height: 32),
          Center(
            child: GestureDetector(
              onTap: () async {
                final url = Uri.parse('https://www.nowdigiverse.com/');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                'Powered by NowDigiverse',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
          SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Spacer(),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
