import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/updates.dart';
import '../widgets/common.dart';

/// Checks GitHub for a newer release and offers to install it (Android) or
/// open the release page (desktop). Silent when nothing is new unless
/// [manual].
Future<void> checkForUpdates(BuildContext context, {bool manual = false}) async {
  final l = context.l;
  final r = await UpdateService.check();
  if (!context.mounted) return;
  if (r == null) {
    if (manual) context.toast(l.upToDateVersion);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (c) => _UpdateDialog(release: r));
}

class _UpdateDialog extends StatefulWidget {
  final ReleaseInfo release;
  const _UpdateDialog({required this.release});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final r = widget.release;
    return AlertDialog(
      title: Text(l.updateAvailable(r.version)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (r.notes.isNotEmpty) Text(r.notes, maxLines: 12, overflow: TextOverflow.ellipsis),
          if (_progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 4),
            Text('${(_progress! * 100).round()}%'),
          ],
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.later)),
        TextButton(onPressed: () => launchUrl(Uri.parse(r.htmlUrl), mode: LaunchMode.externalApplication),
            child: Text(l.openReleasePage)),
        if (UpdateService.canInstall && r.apkUrl != null)
          FilledButton(
            onPressed: _progress != null ? null : () async {
              setState(() { _progress = 0; _error = null; });
              try {
                await UpdateService.downloadAndInstall(r, (p) { if (mounted) setState(() => _progress = p); });
                if (!mounted) return;
                Navigator.of(this.context).pop();
              } catch (e) {
                if (mounted) setState(() { _error = '$e'; _progress = null; });
              }
            },
            child: Text(l.downloadAndInstall),
          ),
      ],
    );
  }
}
