import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_state.dart';
import '../../core/scan_state.dart';
import '../../shared/theme/app_theme.dart';
import 'scanning_screen.dart';
import 'root_explainer_screen.dart';

/// Home / Scan tab — category multi-select + Start Scan trigger (Phase 1).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checkedResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkResumeState();
    });
    
    context.read<ScanState>().onQuickScanTriggered = () {
      if (!mounted) return;
      final scanState = context.read<ScanState>();
      scanState.startScan();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScanningScreen()),
      );
    };
  }

  Future<void> _checkResumeState() async {
    if (_checkedResume || !mounted) return;
    _checkedResume = true;
    
    final scanState = context.read<ScanState>();
    
    final quickScanRequested = await scanState.checkQuickScanIntent();
    if (quickScanRequested && mounted) {
      scanState.startScan();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScanningScreen()),
      );
      return;
    }

    final hasResume = await scanState.hasResumeState();
    
    if (hasResume && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Resume previous scan?'),
          content: Text(
            'An incomplete deep scan was found. Would you like to resume it?',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () {
                scanState.clearResumeState();
                Navigator.of(ctx).pop();
              },
              child: Text('Discard', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: scanState,
                      child: ScanningScreen(),
                    ),
                  ),
                );
                scanState.resumeDeepScan();
              },
              child: Text('Resume'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final scanState = context.watch<ScanState>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('PixelRevive'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _RootBadge(isRooted: appState.isRooted),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero card ──────────────────────────────────────────────────
              _HeroCard(apiLevel: appState.apiLevel),
              SizedBox(height: 28),

              // ── Category filter ────────────────────────────────────────────
              Text(
                'WHAT TO SCAN',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: ScanCategory.values
                    .map((cat) => _CategoryChip(category: cat))
                    .toList(),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.read<ScanState>().selectAllCategories();
                    },
                    child: Text(
                      'Select all',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    '·',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      for (final c in ScanCategory.values) {
                        if (context
                            .read<ScanState>()
                            .selectedCategories
                            .contains(c)) {
                          context.read<ScanState>().toggleCategory(c);
                        }
                      }
                    },
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 28),

              // ── Extended Scan card (Phase 3) ─────────────────────────────
              _ExtendedScanCard(),

              SizedBox(height: 16),

              // ── Deep Scan card (Phase 4) ─────────────────────────────────
              _DeepScanCard(isRooted: appState.isRooted),

              SizedBox(height: 32),

              // ── Start Scan button ──────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: context.read<ScanState>(),
                          child: ScanningScreen(),
                        ),
                      ),
                    );
                    context.read<ScanState>().startScan();
                  },
                  icon: Icon(Icons.search_rounded, size: 22),
                  label: Text(
                    scanState.selectedCategories.isEmpty
                        ? 'Start Scan — All Categories'
                        : 'Start Scan (${scanState.selectedCategories.length} selected)',
                  ),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    textStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 16),

              // ── Storage permission warning (if needed) ─────────────────────
              if (!appState.permissionsGranted)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: AppColors.accentOrange, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Storage permission needed for full scan results.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.accentOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _RootBadge extends StatelessWidget {
  final bool isRooted;
  const _RootBadge({required this.isRooted});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        isRooted ? 'ROOT' : 'NO ROOT',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isRooted ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      backgroundColor: isRooted
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
          : Theme.of(context).colorScheme.surface,
      side: BorderSide(
        color: isRooted
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final int apiLevel;
  const _HeroCard({required this.apiLevel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Icon(
              Icons.manage_search_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 32,
            ),
          ),
          SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Scan',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  apiLevel >= 30
                      ? 'Scans trash bin + WhatsApp media'
                      : 'WhatsApp media scan (Android ${apiLevel < 30 ? "<11" : "11+"})',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _CategoryChip extends StatelessWidget {
  final ScanCategory category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final scanState = context.watch<ScanState>();
    final selected = scanState.selectedCategories.contains(category);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.read<ScanState>().toggleCategory(category);
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category.icon,
              size: 16,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: 8),
            Text(
              category.label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtendedScanCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          HapticFeedback.mediumImpact();
          final scanState = context.read<ScanState>();
          final uri = await scanState.pickSafFolder();
          if (uri != null && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: scanState,
                  child: ScanningScreen(),
                ),
              ),
            );
            scanState.startScan(safUri: uri);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.folder_open_rounded,
                    color: Theme.of(context).colorScheme.secondary, size: 20),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Extended Scan',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Scans a specific folder you choose for additional recoverable files.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeepScanCard extends StatelessWidget {
  final bool isRooted;
  
  const _DeepScanCard({required this.isRooted});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          HapticFeedback.mediumImpact();
          if (isRooted) {
            final scanState = context.read<ScanState>();
            
            // Phase 7: Resource Guard
            final resources = await scanState.checkDeviceResources();
            final batteryLevel = resources['batteryLevel'] as int? ?? 100;
            final isCharging = resources['isCharging'] as bool? ?? true;
            final isHot = resources['isHot'] as bool? ?? false;
            
            if ((batteryLevel < 15 && !isCharging) || isHot) {
              if (!context.mounted) return;
              final proceed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  title: Text('Resource Warning', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  content: Text(
                    isHot
                        ? 'Your device is currently running hot. A deep scan is intensive and may cause it to overheat further or throttle down.'
                        : 'Your battery is below 15% and not charging. A deep scan may drain it completely.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text('Proceed Anyway'),
                    ),
                  ],
                ),
              );
              if (proceed != true) return;
            }
            
            if (!context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: scanState,
                  child: ScanningScreen(),
                ),
              ),
            );
            scanState.startDeepScan();
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RootExplainerScreen()),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isRooted ? Theme.of(context).colorScheme.error.withValues(alpha: 0.3) : Theme.of(context).colorScheme.surfaceContainerHighest),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isRooted ? Theme.of(context).colorScheme.error.withValues(alpha: 0.1) : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.memory_rounded,
                    color: isRooted ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deep Scan (Root)',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Carves files directly from raw storage blocks.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(isRooted ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
                  color: isRooted ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
