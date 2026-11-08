// Offering an update: the dialog (from the daily check, on reopening the app,
// or from More → Check for updates), a banner for the home screens and the
// tile in More. The finding and downloading is UpdateWatcher's job.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/update_watcher.dart';
import '../../platform/updates.dart';
import '../widgets/common.dart';

/// Checks GitHub for a newer release and offers to install it (Android) or
/// open the release page (desktop). [manual] (from More) checks right now
/// and says so when nothing is new or GitHub cannot be reached.
Future<void> checkForUpdates(BuildContext context, {bool manual = false}) async {
  final l = context.l;
  final w = context.app.updates;
  final res = await w.poll(force: manual);
  if (!context.mounted) return;
  if (res != UpdatePoll.found || w.ready == null) {
    if (manual) context.toast(res == UpdatePoll.offline ? l.updateCheckFailed : l.upToDateVersion);
    return;
  }
  await offerUpdate(context);
}

/// Shows the update dialog for what the watcher holds (if anything).
Future<void> offerUpdate(BuildContext context) async {
  final w = context.app.updates;
  if (w.ready == null) return;
  await showDialog<void>(context: context, builder: (c) => _UpdateDialog(watcher: w));
}

/// A card "Version X is ready to install" with the install button, for the
/// top of the home screens; nothing when there is no update.
class UpdateReadyBanner extends StatelessWidget {
  const UpdateReadyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return ListenableBuilder(
      listenable: context.app.updates,
      builder: (context, _) {
        final w = context.app.updates;
        final r = w.ready;
        if (r == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Card(
          color: scheme.primaryContainer,
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: ListTile(
            leading: Icon(Icons.system_update, color: scheme.onPrimaryContainer),
            title: Text(l.updateReady(r.version),
                style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
            subtitle: Text(w.apk == null && UpdateService.canInstall ? l.updateDownloading : l.updateReadyHelp,
                style: TextStyle(color: scheme.onPrimaryContainer)),
            onTap: () => offerUpdate(context),
          ),
        );
      },
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateWatcher watcher;
  const _UpdateDialog({required this.watcher});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final w = widget.watcher;
    final r = w.ready!;
    final downloaded = w.apk != null;
    return AlertDialog(
      title: Text(downloaded ? l.updateReady(r.version) : l.updateAvailable(r.version)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (downloaded) ...[
            Text(l.updateReadyHelp, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
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
        TextButton(
          onPressed: () {
            w.offered();
            Navigator.pop(context);
          },
          child: Text(l.later),
        ),
        TextButton(onPressed: () => launchUrl(Uri.parse(r.htmlUrl), mode: LaunchMode.externalApplication),
            child: Text(l.openReleasePage)),
        if (UpdateService.canInstall && r.apkUrl != null)
          FilledButton(
            onPressed: _progress != null ? null : () async {
              setState(() { _progress = downloaded ? null : 0; _error = null; });
              try {
                final apk = w.apk;
                if (apk != null) {
                  await UpdateService.install(apk);
                } else {
                  await UpdateService.downloadAndInstall(r, (p) { if (mounted) setState(() => _progress = p); });
                }
                if (!mounted) return;
                Navigator.of(this.context).pop();
              } catch (e) {
                if (mounted) setState(() { _error = '$e'; _progress = null; });
              }
            },
            child: Text(downloaded ? l.installNow : l.downloadAndInstall),
          ),
      ],
    );
  }
}
