// Showing people: the name this device knows them by (nickname > their
// profile > the member row), their profile picture, and the nickname editor.

import 'package:flutter/material.dart';

import '../../data/queries.dart';
import '../../identity/identity_service.dart';
import 'attachments.dart';
import 'common.dart';

/// The name to show for [pubkey]: "You" for ourselves without a name,
/// else the best known name, else the short npub.
String personName(BuildContext context, String pubkey, Map<String, Person> people) {
  final n = people[pubkey]?.name;
  if (n != null && n.isNotEmpty) return n;
  return pubkey == context.app.identity.pubkey ? context.l.you : shortNpub(pubkey);
}

class PersonAvatar extends StatelessWidget {
  final String pubkey;
  final Map<String, Person> people;
  final double radius;
  const PersonAvatar({super.key, required this.pubkey, required this.people, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final p = people[pubkey];
    if (p?.photo != null) return PhotoAvatar(sha: p!.photo, icon: Icons.person, radius: radius);
    final n = p?.name;
    return CircleAvatar(
      radius: radius,
      child: n == null || n.isEmpty
          ? Icon(Icons.person, size: radius)
          : Text(n.characters.first.toUpperCase(), style: TextStyle(fontSize: radius * 0.9)),
    );
  }
}

/// Lets this device give [pubkey] a nickname (kept here only; the person
/// never sees it).
Future<void> editNickname(BuildContext context, String pubkey) async {
  final l = context.l;
  final app = context.app;
  final current = (await app.q.nicknames())[pubkey];
  if (!context.mounted) return;
  final ctrl = TextEditingController(text: current ?? '');
  final v = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(l.nickname),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l.nicknameHelp, style: Theme.of(c).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: l.nickname),
            onSubmitted: (s) => Navigator.pop(c, s)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
        if (current != null) TextButton(onPressed: () => Navigator.pop(c, ''), child: Text(l.remove)),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(l.save)),
      ],
    ),
  );
  ctrl.dispose();
  if (v == null) return;
  await app.q.setNickname(pubkey, v);
  app.ledger.touch();
}
