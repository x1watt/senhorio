// My profile: the name and picture everyone I share a building with sees.

import 'package:flutter/material.dart';

import '../../data/schema.dart';
import '../../data/zx_store.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  String? _loadedName;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(String? field, Object? value) => guarded(context, () => context.app.ledger
      .upsert('profiles', globalBuilding, {field!: value}, id: context.app.identity.pubkey));

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final me = context.app.identity.pubkey;
    return Scaffold(
      appBar: AppBar(title: Text(l.myProfile)),
      body: LiveFuture<DbRow?>(
        load: (a) => a.q.profile(me),
        builder: (context, p) {
          final name = p?['name'] as String?;
          if (_loadedName != name) {
            _loadedName = name;
            _name.text = name ?? '';
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Center(
              child: Stack(children: [
                PhotoAvatar(sha: p?['photo'] as String?, icon: Icons.person, radius: 56),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: FilledButton(
                    style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(10)),
                    onPressed: () async {
                      final sha = await pickPhoto(context);
                      if (sha != null) await _save('photo', sha);
                    },
                    child: const Icon(Icons.add_a_photo, size: 20),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l.name,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: l.save,
                  onPressed: () => _save('name', _name.text.trim().isEmpty ? null : _name.text.trim()),
                ),
              ),
              onSubmitted: (s) => _save('name', s.trim().isEmpty ? null : s.trim()),
            ),
            const SizedBox(height: 12),
            Text(l.myProfileHelp, style: Theme.of(context).textTheme.bodySmall),
          ]);
        },
      ),
    );
  }
}
