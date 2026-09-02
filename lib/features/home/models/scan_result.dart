import 'dart:io';
import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ScanCategory enum
// ─────────────────────────────────────────────────────────────────────────────

enum ScanCategory {
  photos('photos', 'Photos', Icons.photo_library_rounded),
  videos('videos', 'Videos', Icons.video_library_rounded),
  whatsapp('whatsapp', 'WhatsApp', Icons.chat_rounded),
  documents('documents', 'Documents', Icons.description_rounded),
  audio('audio', 'Audio', Icons.music_note_rounded);

  final String id;
  final String label;
  final IconData icon;
  const ScanCategory(this.id, this.label, this.icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// ScanResult model
// ─────────────────────────────────────────────────────────────────────────────

class ScanResult {
  final String uri;
  final String path;
  final String name;
  final int dateDeleted; // milliseconds since epoch
  final int size; // bytes
  final String mimeType;
  final String source; // 'trash' | 'whatsapp'
  final int confidence; // 0–100
  final String thumbnailPath;
  bool isSelected;

  ScanResult({
    required this.uri,
    required this.path,
    required this.name,
    required this.dateDeleted,
    required this.size,
    required this.mimeType,
    required this.source,
    required this.confidence,
    required this.thumbnailPath,
    this.isSelected = false,
  });

  factory ScanResult.fromMap(Map<String, dynamic> map) {
    return ScanResult(
      uri: map['uri'] as String? ?? '',
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown',
      dateDeleted: (map['dateDeleted'] as num?)?.toInt() ?? 0,
      size: (map['size'] as num?)?.toInt() ?? 0,
      mimeType: map['mimeType'] as String? ?? '',
      source: map['source'] as String? ?? '',
      confidence: (map['confidence'] as num?)?.toInt() ?? 0,
      thumbnailPath: map['thumbnailPath'] as String? ?? '',
    );
  }

  // ── Derived helpers ────────────────────────────────────────────────────────

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isDocument =>
      mimeType.startsWith('application/') || mimeType.startsWith('text/');

  /// Human-readable file size.
  String get formattedSize {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Human-readable date.
  String get formattedDate {
    if (dateDeleted == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(dateDeleted);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  /// Color-coded confidence badge color.
  Color confidenceColor(BuildContext context) {
    if (confidence >= 80) return Theme.of(context).colorScheme.primary;
    if (confidence >= 40) return AppColors.accentOrange;
    return Theme.of(context).colorScheme.error;
  }

  IconData get typeIcon {
    if (isImage) return Icons.image_rounded;
    if (isVideo) return Icons.videocam_rounded;
    if (isAudio) return Icons.music_note_rounded;
    if (isDocument) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color typeColor(BuildContext context) {
    if (isImage) return Theme.of(context).colorScheme.primary;
    if (isVideo) return Theme.of(context).colorScheme.secondary;
    if (isAudio) return AppColors.accentOrange;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  /// Build a thumbnail widget.
  Widget buildThumbnail(BuildContext context, {double size = 80.0}) {
    if (thumbnailPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(thumbnailPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _typeIconWidget(context, size),
        ),
      );
    }
    return _typeIconWidget(context, size);
  }

  Widget _typeIconWidget(BuildContext context, double sz) {
    return Container(
      width: sz,
      height: sz,
      decoration: BoxDecoration(
        color: typeColor(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(typeIcon, color: typeColor(context), size: sz * 0.45),
    );
  }
}
