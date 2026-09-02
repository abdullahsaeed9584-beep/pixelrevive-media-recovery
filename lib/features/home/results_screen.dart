import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/scan_state.dart';
import 'recovery_success_screen.dart';

/// Results grid — thumbnail + filename + size + date, checkbox multi-select,
/// Recover Selected button. Reusable for Phase 3 SAF extended scan.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scanState = context.watch<ScanState>();
    final results = scanState.results;
    final selectedCount = scanState.selectedCount;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          results.isEmpty
              ? 'No Results'
              : '${results.length} file${results.length == 1 ? '' : 's'} found',
        ),
        actions: [
          if (results.isNotEmpty)
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                if (selectedCount == results.length) {
                  scanState.deselectAll();
                } else {
                  scanState.selectAll();
                }
              },
              child: Text(
                selectedCount == results.length ? 'Deselect All' : 'Select All',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: results.isEmpty
          ? _EmptyResults()
          : Column(
              children: [
                // ── Filter row ───────────────────────────────────────────────
                _FilterBar(results: results),

                // ── Grid ─────────────────────────────────────────────────────
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      return _ResultCard(result: results[i]);
                    },
                  ),
                ),

                // ── Bottom action bar ─────────────────────────────────────────
                if (selectedCount > 0)
                  _RecoverBar(
                    selectedCount: selectedCount,
                    recovering: scanState.recovering,
                    onRecover: () async {
                      HapticFeedback.mediumImpact();
                      
                      // Phase 7: Storage Pre-check
                      final availableBytes = await scanState.checkAvailableStorage();
                      final requiredBytes = scanState.selectedResults.fold<int>(0, (sum, r) => sum + r.size);
                      
                      // Add 50MB buffer
                      if (availableBytes < requiredBytes + 50 * 1024 * 1024) {
                        if (!context.mounted) return;
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            title: Text('Insufficient Storage', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                            content: Text(
                              'You do not have enough free space on your device to recover these files. Please free up some space and try again.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: Text('OK', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      final recovered = await scanState.recoverSelected();
                      if (context.mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: context.read<ScanState>(),
                              child: RecoverySuccessScreen(
                                  recoveredItems: recovered),
                            ),
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter bar — source badges summary
// ─────────────────────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final List<ScanResult> results;
  const _FilterBar({required this.results});

  @override
  Widget build(BuildContext context) {
    final trashCount = results.where((r) => r.source == 'trash').length;
    final waCount = results.where((r) => r.source == 'whatsapp').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHighest),
        ),
      ),
      child: Row(
        children: [
          if (trashCount > 0)
            _SourceBadge(label: '🗑 $trashCount from Trash',
                color: Theme.of(context).colorScheme.primary),
          if (trashCount > 0 && waCount > 0) SizedBox(width: 8),
          if (waCount > 0)
            _SourceBadge(label: '💬 $waCount WhatsApp',
                color: Theme.of(context).colorScheme.secondary),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SourceBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Result card
// ─────────────────────────────────────────────────────────────────────────────
class _ResultCard extends StatelessWidget {
  final ScanResult result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final scanState = context.watch<ScanState>();

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        scanState.toggleSelect(result);
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: result.isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: result.isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            width: result.isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Stack(
                children: [
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: result.buildThumbnail(context, size: 120.0),
                  ),
                  // Confidence badge (Phase 5 will expand this)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${result.confidence}%',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: result.confidenceColor(context),
                        ),
                      ),
                    ),
                  ),
                  // Checkbox overlay
                  Positioned(
                    top: 6,
                    left: 6,
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: result.isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: result.isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          width: 1.5,
                        ),
                      ),
                      child: result.isSelected
                          ? Icon(Icons.check_rounded,
                              size: 14, color: Theme.of(context).colorScheme.onPrimary)
                          : null,
                    ),
                  ),
                  // Source icon
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Text(
                      result.source == 'trash' ? '🗑' : '💬',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),

            // Metadata
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '${result.formattedSize} · ${result.formattedDate}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recover action bar
// ─────────────────────────────────────────────────────────────────────────────
class _RecoverBar extends StatelessWidget {
  final int selectedCount;
  final bool recovering;
  final VoidCallback onRecover;
  const _RecoverBar({
    required this.selectedCount,
    required this.recovering,
    required this.onRecover,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHighest),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: recovering ? null : onRecover,
          icon: recovering
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : Icon(Icons.restore_rounded),
          label: Text(
            recovering
                ? 'Recovering…'
                : 'Recover $selectedCount file${selectedCount == 1 ? '' : 's'}',
          ),
          style: ElevatedButton.styleFrom(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: Theme.of(context).colorScheme.primary,
            textStyle: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyResults extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 48,
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Nothing to recover',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'No deleted files found in the trash or\nWhatsApp folders for selected categories.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.search_rounded),
            label: Text('Scan again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
