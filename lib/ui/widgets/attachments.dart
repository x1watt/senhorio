// Picking, storing (by SHA-256 in `attachments`) and showing photos and
// PDFs: receipts of expenses, identification documents of tenants.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'common.dart';

/// Re-encodes a photo as a JPEG at most 1600 px on its long side.
Uint8List shrinkImage(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) return bytes;
  final long = im.width > im.height ? im.width : im.height;
  final out = long > 1600
      ? img.copyResize(im, width: im.width >= im.height ? 1600 : null, height: im.height > im.width ? 1600 : null)
      : im;
  final jpg = img.encodeJpg(out, quality: 80);
  return jpg.length < bytes.length ? jpg : bytes;
}

/// Lets the user take or pick a photo (or a file) and stores it; returns
/// the SHA-256, or null when cancelled.
Future<String?> pickAndStoreAttachment(BuildContext context, {ImageSource? source, bool imagesOnly = false}) async {
  Uint8List? bytes;
  var mime = 'image/jpeg';
  if (source != null) {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (x == null) return null;
    bytes = await x.readAsBytes();
  } else {
    final f = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'images', extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic']),
      if (!imagesOnly) const XTypeGroup(label: 'pdf', extensions: ['pdf']),
    ]);
    if (f == null) return null;
    bytes = await f.readAsBytes();
    if (f.name.toLowerCase().endsWith('.pdf')) mime = 'application/pdf';
  }
  if (mime == 'image/jpeg') bytes = kIsWeb ? shrinkImage(bytes) : await compute(shrinkImage, bytes);
  if (!context.mounted) return null;
  return context.app.q.putAttachment(bytes, mime);
}

bool get _hasCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Asks where a photo comes from (camera, gallery, file) and stores it;
/// returns the SHA-256, or null when cancelled.
Future<String?> pickPhoto(BuildContext context) async {
  final l = context.l;
  if (!_hasCamera) return pickAndStoreAttachment(context, imagesOnly: true);
  final source = await showModalBottomSheet<ImageSource?>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera), title: Text(l.camera),
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: Text(l.gallery),
            onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );
  if (source == null || !context.mounted) return null;
  return pickAndStoreAttachment(context, source: source, imagesOnly: true);
}

/// The stored image [sha] (a placeholder [icon] while it is missing).
class StoredImage extends StatelessWidget {
  final String? sha;
  final IconData icon;
  final BoxFit fit;
  const StoredImage({super.key, required this.sha, required this.icon, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final s = sha;
    if (s == null || s.isEmpty) return Icon(icon, color: Theme.of(context).colorScheme.outline);
    return FutureBuilder<Uint8List?>(
      future: context.app.q.attachment(s),
      builder: (context, snap) => snap.data == null
          ? Icon(icon, color: Theme.of(context).colorScheme.outline)
          : Image.memory(snap.data!, fit: fit, width: double.infinity, height: double.infinity,
              gaplessPlayback: true),
    );
  }
}

/// A round picture (a building, an apartment, a room, a person).
class PhotoAvatar extends StatelessWidget {
  final String? sha;
  final IconData icon;
  final double radius;
  const PhotoAvatar({super.key, required this.sha, required this.icon, this.radius = 20});

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ClipOval(
          child: SizedBox(width: radius * 2, height: radius * 2,
              child: StoredImage(sha: sha, icon: icon)),
        ),
      );
}

/// A wide presentation picture at the top of a screen, with a button to
/// change it when [onChange] is given.
class PhotoBanner extends StatelessWidget {
  final String? sha;
  final IconData icon;
  final Future<void> Function(String sha)? onChange;
  const PhotoBanner({super.key, required this.sha, required this.icon, this.onChange});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final empty = sha == null || sha!.isEmpty;
    if (empty && onChange == null) return const SizedBox.shrink();
    return SizedBox(
      height: empty ? 72 : 200,
      child: Stack(fit: StackFit.expand, children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: StoredImage(sha: sha, icon: icon),
        ),
        if (onChange != null)
          Positioned(
            right: 8,
            bottom: 8,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.add_a_photo, size: 18),
              label: Text(empty ? l.addPhoto : l.changePhoto),
              onPressed: () async {
                final s = await pickPhoto(context);
                if (s != null) await onChange!(s);
              },
            ),
          ),
      ]),
    );
  }
}

/// Saves a new presentation photo on [table] row [id].
Future<void> setEntityPhoto(BuildContext context, String table, String building, String id, String sha) =>
    guarded(context, () => context.app.ledger.upsert(table, building, {'photo': sha}, id: id));

/// Thumbnails of [shas] plus the buttons to add more; [onChanged] gets the
/// new list. Read-only when [onChanged] is null.
class AttachmentList extends StatelessWidget {
  final List<String> shas;
  final void Function(List<String>)? onChanged;
  const AttachmentList({super.key, required this.shas, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    Future<void> add(ImageSource? source) async {
      final sha = await pickAndStoreAttachment(context, source: source);
      if (sha != null && !shas.contains(sha)) onChanged!([...shas, sha]);
    }

    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final sha in shas)
        AttachmentThumb(sha: sha,
            onRemove: onChanged == null ? null : () => onChanged!(shas.where((f) => f != sha).toList())),
      if (onChanged != null) ...[
        if (_hasCamera) _AddButton(icon: Icons.photo_camera, label: l.camera, onTap: () => add(ImageSource.camera)),
        if (_hasCamera) _AddButton(icon: Icons.photo_library, label: l.gallery, onTap: () => add(ImageSource.gallery)),
        _AddButton(icon: Icons.attach_file, label: l.file, onTap: () => add(null)),
      ],
    ]);
  }
}

class _AddButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 84,
        height: 84,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon),
            Text(label, style: const TextStyle(fontSize: 11)),
          ]),
        ),
      );
}

class AttachmentThumb extends StatelessWidget {
  final String sha;
  final VoidCallback? onRemove;
  const AttachmentThumb({super.key, required this.sha, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: context.app.q.attachment(sha),
      builder: (context, snap) {
        final bytes = snap.data;
        final isPdf = bytes != null && bytes.length > 4 && String.fromCharCodes(bytes.sublist(0, 4)) == '%PDF';
        Widget child;
        if (bytes == null) {
          child = snap.connectionState == ConnectionState.done
              ? Tooltip(message: context.l.waitingForSync, child: const Icon(Icons.cloud_download))
              : const CircularProgressIndicator();
        } else if (isPdf) {
          child = const Icon(Icons.picture_as_pdf, size: 40);
        } else {
          child = Image.memory(bytes, fit: BoxFit.cover, width: 84, height: 84);
        }
        return Stack(children: [
          InkWell(
            onTap: bytes == null || isPdf
                ? null
                : () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(),
                      backgroundColor: Colors.black,
                      body: InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(bytes))),
                    ))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 84,
                height: 84,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: child,
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              right: 0,
              top: 0,
              child: InkWell(
                onTap: onRemove,
                child: const CircleAvatar(radius: 11, child: Icon(Icons.close, size: 14)),
              ),
            ),
        ]);
      },
    );
  }
}
