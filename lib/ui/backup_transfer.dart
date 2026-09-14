import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/controller.dart';
import '../platform/pairing.dart';
import 'common.dart';

Future<void> transferBackup(BuildContext context, AppController app) async {
  final password = TextEditingController();
  var upload = app.profiles.isEmpty;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Transfer a backup'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: const Text('Export'),
                    enabled: app.profiles.isNotEmpty,
                  ),
                  const ButtonSegment(value: true, label: Text('Restore')),
                ],
                selected: {upload},
                onSelectionChanged: (s) => set(() => upload = s.first),
              ),
              const SizedBox(height: 20),
              Text(
                upload
                    ? 'Send an encrypted backup from your phone or PC. Restoring replaces this device’s data.'
                    : 'Download this device’s encrypted backup from your phone or PC.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Backup password',
                  helperText: 'At least 10 characters',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) {
    password.dispose();
    return;
  }
  final secret = password.text;
  password.dispose();
  await perform(context, () async {
    if (secret.length < 10) {
      throw const FormatException(
        'Use at least 10 characters for the backup password.',
      );
    }
    final server = PairingServer();
    String? incoming;
    BuildContext? dialog;
    final archive = upload ? null : await app.exportBackup(secret);
    if (archive != null && archive.length > 64 * 1024 * 1024) {
      throw const FormatException(
        'This backup exceeds the 64 MB QR transfer limit. Use file export.',
      );
    }
    await server.start(
      (p) {
        incoming = p['backup'];
        if (dialog?.mounted == true) Navigator.pop(dialog!);
      },
      transfer: true,
      backup: archive,
    );
    try {
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (c) {
          dialog = c;
          return AlertDialog(
            title: const Text('Scan to connect'),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Use a phone or PC on the same network. This transfer expires in 5 minutes.',
                  ),
                  const SizedBox(height: 20),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(data: server.url, size: 240),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } finally {
      await server.close();
    }
    if (incoming != null &&
        context.mounted &&
        await confirm(
          context,
          'Replace this device’s data?',
          'The received backup will replace all profiles and library data. A rollback snapshot will be saved.',
        )) {
      await app.restoreBackup(incoming!, secret);
    }
  });
}
