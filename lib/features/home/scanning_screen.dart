import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/scan_state.dart';
import 'results_screen.dart';
import 'widgets/confidence_badge.dart';

/// Live scanning screen — progress bar + streaming thumbnail grid.
/// Navigates automatically to ResultsScreen when scan completes.
class ScanningScreen extends StatefulWidget {
  const ScanningScreen({super.key});

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onScanDone(BuildContext context, ScanState scanState) {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: scanState,
          child: ResultsScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanState = context.watch<ScanState>();

    // Auto-navigate when scan finishes.
    if (scanState.status == ScanStatus.done && !_navigated) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onScanDone(context, scanState),
      );
    }

    final isPaused = scanState.status == ScanStatus.paused;
    final isScanning = scanState.status == ScanStatus.scanning;

    if (isPaused) {
      _pulseCtrl.stop();
    } else if (isScanning && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }

    final resultCount = scanState.results.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(isPaused ? 'Paused' : 'Scanning…'),
        automaticallyImplyLeading: false,
        actions: [
          if (isPaused)
            TextButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                scanState.resumeDeepScan();
              },
              child: Text(
                'Resume',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (isScanning)
            TextButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                scanState.pauseScan();
              },
              child: Text(
                'Pause',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              scanState.cancelScan();
              _onScanDone(context, scanState);
            },
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Animated progress bar ──────────────────────────────────────────
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, child) => LinearProgressIndicator(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary,
                        _pulseCtrl.value) ??
                    Theme.of(context).colorScheme.primary,
              ),
            ),
          ),

          SizedBox(height: 16),

          // ── Result count badge ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  child: Text(
                    key: ValueKey('$resultCount-$isPaused'),
                    resultCount == 0
                        ? (isPaused ? 'Scan paused' : 'Searching…')
                        : '$resultCount recoverable file${resultCount == 1 ? '' : 's'} found',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Spacer(),
                if (resultCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '+$resultCount',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          SizedBox(height: 12),

          // ── Streaming grid ─────────────────────────────────────────────────
          Expanded(
            child: resultCount == 0
                ? _EmptyState(pulseCtrl: _pulseCtrl, isPaused: isPaused)
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1,
                    ),
                    itemCount: resultCount,
                    itemBuilder: (context, i) {
                      final r = scanState.results[i];
                      return _ScanTile(result: r);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScanTile extends StatelessWidget {
  final dynamic result;
  const _ScanTile({required this.result});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          result.buildThumbnail(context, size: 120.0),
          // Source badge
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                result.source == 'trash' ? '🗑' : '💬',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
          // Confidence badge
          if (result.confidence != null)
            Positioned(
              top: 4,
              right: 4,
              child: ConfidenceBadge(confidence: result.confidence),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AnimationController pulseCtrl;
  final bool isPaused;
  const _EmptyState({required this.pulseCtrl, required this.isPaused});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: pulseCtrl,
            builder: (context, child) => Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: 0.05 + pulseCtrl.value * 0.1,
                ),
              ),
              child: Icon(
                isPaused ? Icons.pause_circle_outline : Icons.radar_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 40,
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            isPaused ? 'Scan paused' : 'Scanning device…',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Results appear here as they\'re found',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
