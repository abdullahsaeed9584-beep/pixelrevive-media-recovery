import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/protection_state.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final TextEditingController _pinController = TextEditingController();
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<ProtectionState>().isVaultUnlocked) {
        context.read<ProtectionState>().loadVaultFiles();
      }
    });
    
    _lockoutTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        final state = context.read<ProtectionState>();
        if (state.isLockedOut || _pinController.text.isEmpty) {
          setState(() {}); // Rebuild to update countdown or unlock when time expires
        }
      }
    });
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProtectionState>();

    if (!state.hasPin) {
      return Scaffold(
        body: Center(child: Text('Protection Mode not set up yet.')),
      );
    }

    if (!state.isVaultUnlocked) {
      return _buildLockScreen(context, state);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Encrypted Vault'),
        actions: [
          IconButton(
            icon: Icon(Icons.lock_outline),
            onPressed: () => state.lockVault(),
          )
        ],
      ),
      body: state.vaultFiles.isEmpty
          ? Center(child: Text('Vault is empty.'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: state.vaultFiles.length,
              itemBuilder: (context, index) {
                final file = state.vaultFiles[index];
                return _VaultItem(file: file);
              },
            ),
    );
  }

  Widget _buildLockScreen(BuildContext context, ProtectionState state) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Theme.of(context).colorScheme.primary),
              SizedBox(height: 24),
              Text(
                state.isLockedOut
                    ? 'Too many attempts. Locked for ${state.remainingLockout.inSeconds}s.'
                    : 'Enter Vault PIN',
                style: TextStyle(
                    fontSize: 20,
                    color: state.isLockedOut ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurface),
              ),
              SizedBox(height: 16),
              if (!state.isLockedOut) ...[
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  onChanged: (val) async {
                    if (val.length == 4) {
                      final success = await state.verifyPin(val);
                      if (!context.mounted) return;
                      if (success) {
                        _pinController.clear();
                        state.loadVaultFiles();
                      } else {
                        _pinController.clear();
                        if (state.isLockedOut) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Vault locked due to too many attempts.')),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Incorrect PIN')),
                          );
                        }
                      }
                    }
                  },
                ),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: Icon(Icons.fingerprint),
                  label: Text('Unlock with Biometrics'),
                  onPressed: () async {
                    final success = await state.verifyBiometric();
                    if (success) {
                      state.loadVaultFiles();
                    }
                  },
                )
              ] else ...[
                SizedBox(height: 48), // Spacer when locked out
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultItem extends StatefulWidget {
  final Map<String, dynamic> file;
  const _VaultItem({required this.file});

  @override
  State<_VaultItem> createState() => _VaultItemState();
}

class _VaultItemState extends State<_VaultItem> {
  String? _thumbnailPath;
  bool _isLoadingThumb = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final hasThumb = widget.file['hasThumbnail'] == true;
    if (!hasThumb) return;

    if (mounted) setState(() => _isLoadingThumb = true);
    final state = context.read<ProtectionState>();
    final path = await state.decryptFileToCache(widget.file['encryptedName'], isThumbnail: true);
    if (mounted) {
      setState(() {
        _thumbnailPath = path;
        _isLoadingThumb = false;
      });
    }
  }

  void _openPreview(BuildContext context) async {
    final state = context.read<ProtectionState>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator()),
    );

    final path = await state.decryptFileToCache(widget.file['encryptedName']);
    if (!context.mounted) return;
    Navigator.pop(context); // close loading

    if (path != null) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                top: 40,
                right: 16,
                child: IconButton(
                  icon: Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.pop(context),
                ),
              )
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProtectionState>();
    final originalName = widget.file['originalName'] as String;
    final encryptedName = widget.file['encryptedName'] as String;

    return GestureDetector(
      onTap: () => _openPreview(context),
      child: Card(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoadingThumb)
              Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_thumbnailPath != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_thumbnailPath!),
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: Icon(Icons.insert_drive_file, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.share_rounded, color: Theme.of(context).colorScheme.primary),
                tooltip: 'Share',
                onPressed: () async {
                  final path = await state.decryptFile(encryptedName);
                  if (path != null && context.mounted) {
                    Share.shareXFiles([XFile(path)], text: 'Protected with PixelRevive'); // ignore: deprecated_member_use
                    // Optionally we could delete the temporary decrypted file here or later
                  }
                },
              ),
              IconButton(
                icon: Icon(Icons.restore, color: Theme.of(context).colorScheme.primary),
                tooltip: 'Restore',
                onPressed: () async {
                  final path = await state.decryptFile(encryptedName);
                  if (path != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Restored to Downloads/Recovered')),
                    );
                    state.deleteFile(encryptedName); // Remove from vault after restore
                  }
                },
              ),
              IconButton(
                icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                tooltip: 'Delete',
                onPressed: () => state.deleteFile(encryptedName),
              ),
            ],
          )
        ],
      ),
    ),
  );
}
}
