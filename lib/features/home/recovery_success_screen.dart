import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/scan_state.dart';

/// Recovery success screen — shows recovered files list with
/// Open File and Share buttons. No extra gallery-hunting step.
class RecoverySuccessScreen extends StatelessWidget {
  final List<Map<String, dynamic>> recoveredItems;

  const RecoverySuccessScreen({super.key, required this.recoveredItems});

  int get _successCount =>
      recoveredItems.where((i) => i['success'] == true).length;

  @override
  Widget build(BuildContext context) {
    final scanState = context.read<ScanState>();
    final successful =
        recoveredItems.where((i) => i['success'] == true).toList();
    final failed =
        recoveredItems.where((i) => i['success'] != true).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Recovery Complete'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              // Return all the way to Home and reset scan.
              Navigator.of(context).popUntil((route) => route.isFirst);
              scanState.resetScan();
            },
            child: Text(
              'Done',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Success header ─────────────────────────────────────────────────
          _SuccessHeader(
            successCount: _successCount,
            failedCount: failed.length,
          ),

          // ── Files list ─────────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: successful.length,
              itemBuilder: (context, i) {
                final item = successful[i];
                final destPath = item['destPath'] as String? ?? '';
                final name = item['name'] as String? ?? 'Unknown';
                return _RecoveredFileTile(
                  name: name,
                  destPath: destPath,
                  onOpen: () => scanState.openFile(destPath),
                );
              },
            ),
          ),

          // ── Failed items warning ───────────────────────────────────────────
          if (failed.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: Theme.of(context).colorScheme.error, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${failed.length} file${failed.length == 1 ? '' : 's'} could not be recovered.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Bottom CTA ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  scanState.resetScan();
                },
                icon: Icon(Icons.search_rounded),
                label: Text('New Scan'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SuccessHeader extends StatelessWidget {
  final int successCount;
  final int failedCount;
  const _SuccessHeader(
      {required this.successCount, required this.failedCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            Theme.of(context).scaffoldBackgroundColor,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary, size: 42),
          ),
          SizedBox(height: 16),
          Text(
            '$successCount file${successCount == 1 ? '' : 's'} recovered',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Saved to Downloads/Recovered/',
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

class _RecoveredFileTile extends StatelessWidget {
  final String name;
  final String destPath;
  final VoidCallback onOpen;

  const _RecoveredFileTile({
    required this.name,
    required this.destPath,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toUpperCase()
        : '?';
    final file = File(destPath);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      ),
      child: Row(
        children: [
          // Ext badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                ext.length > 4 ? ext.substring(0, 4) : ext,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),

          // File info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  destPath.isNotEmpty
                      ? destPath
                          .replaceFirst(RegExp(r'^.*/'), '…/')
                          .substring(0, destPath.length > 40 ? 40 : destPath.length - 1)
                      : 'Download/Recovered/',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Share button
          if (destPath.isNotEmpty && file.existsSync())
            IconButton(
              icon: Icon(Icons.share_rounded, color: Theme.of(context).colorScheme.primary),
              onPressed: () {
                HapticFeedback.lightImpact();
                Share.shareXFiles([XFile(destPath)], text: 'Recovered with PixelRevive'); // ignore: deprecated_member_use
              },
            ),

          // Open button
          if (destPath.isNotEmpty && file.existsSync())
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onOpen();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Open',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
