import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/protection_state.dart';

class ProtectionScreen extends StatelessWidget {
  const ProtectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProtectionState>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text('Protection Mode')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              title: Text('Enable Protection'),
              value: state.isProtectionEnabled,
              onChanged: (val) async {
                if (val && !state.hasPin) {
                  // Prompt for PIN creation first
                  final pin = await _showPinDialog(context, create: true);
                  if (pin != null) {
                    await state.setPin(pin);
                    state.toggleProtection(true);
                  }
                } else {
                  state.toggleProtection(val);
                }
              },
            ),
            if (state.isProtectionEnabled) ...[
              SizedBox(height: 20),
              Text('Monitored Folders'),
              _FolderCheckbox(label: 'Gallery (DCIM)', path: 'DCIM'),
              _FolderCheckbox(label: 'Pictures', path: 'Pictures'),
              _FolderCheckbox(label: 'Movies', path: 'Movies'),
              _FolderCheckbox(label: 'WhatsApp Images', path: 'WhatsApp/Media/WhatsApp Images'),
              _FolderCheckbox(label: 'Downloads', path: 'Download'),
            ],
          ],
        ),
      ),
    );
  }

  Future<String?> _showPinDialog(BuildContext context, {required bool create}) {
    String pin = '';
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(create ? 'Create PIN' : 'Enter PIN'),
        content: TextField(
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          onChanged: (v) => pin = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, pin), child: Text('OK')),
        ],
      ),
    );
  }
}

class _FolderCheckbox extends StatelessWidget {
  final String label;
  final String path;

  const _FolderCheckbox({required this.label, required this.path});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProtectionState>();
    final isMonitored = state.monitoredFolders.contains(path);

    return CheckboxListTile(
      title: Text(label),
      value: isMonitored,
      onChanged: (val) {
        final current = List<String>.from(state.monitoredFolders);
        if (val == true) {
          current.add(path);
        } else {
          current.remove(path);
        }
        state.updateFolders(current);
      },
    );
  }
}
