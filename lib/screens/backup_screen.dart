import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../widgets/player_scaffold.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  Future<void> _run(bool importing) async {
    final library = context.read<LibraryState>();
    final l = L10n.of(context);
    setState(() => _busy = true);
    try {
      if (importing) {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (file == null) return;
        if ((await file.length() ?? 0) > 50 * 1024 * 1024) {
          throw FormatException(l('backup.tooLarge'));
        }
        final source = utf8.decode(await file.readAsBytes());
        await library.importBackup(source);
      } else {
        final source = await library.exportBackup();
        final saved = await FilePicker.saveFile(
          fileName:
              'asmr-one-${DateTime.now().toIso8601String().substring(0, 10)}.json',
          mimeType: 'application/json',
          bytes: Uint8List.fromList(utf8.encode(source)),
        );
        if (saved == null) return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l('backup.done'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${l('backup.failed')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PlayerScaffold(
      appBar: AppBar(title: Text(l('backup.title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.import_export_rounded,
                    color: scheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 14),
                Text(l('backup.title'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  l('backup.hint'),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(false),
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(l('backup.export')),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(true),
            icon: const Icon(Icons.file_download_outlined),
            label: Text(l('backup.import')),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}
