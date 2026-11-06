// Invite codes: a short code ("AB49") that lets someone running the app
// join a building with a role chosen by whoever made the code.
//
// - The code is made and kept on the inviter's device only (table
//   `invites`). It works once, for 24 hours.
// - While a code is open, the inviter's node adds a 1-byte tag,
//   sha256("senhorio-invite:" + code)[0], to its Reticulum announce.
// - The joiner computes the same tag and sends `{t: join, code}` (LXMF, end
//   to end encrypted) only to the nodes announcing that tag.
// - The inviter checks the code and adds the joiner's npub (verified by the
//   announce binding) as a member with the code's role; the normal sync
//   then sends the building. The answer is `join-ok` or `join-fail`.
// - After 20 wrong codes all open codes are cancelled (guessing).

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/ledger.dart';
import '../data/zx_store.dart';
import '../domain/roles.dart';
import 'sync_engine.dart';

/// No 0/O or 1/I, so a code read aloud or on paper is not misread.
const inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const inviteLength = 4;
const inviteLifetime = Duration(hours: 24);
const maxWrongCodes = 20;

/// Upper-cases [s] and drops spaces and dashes; null if it cannot be a code.
String? normalizeInviteCode(String s) {
  final c = s.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (c.length != inviteLength) return null;
  for (final ch in c.split('')) {
    if (!inviteAlphabet.contains(ch)) return null;
  }
  return c;
}

/// The announce tag of [code] (one byte: it only narrows who is asked).
int inviteTag(String code) =>
    sha256.convert(utf8.encode('senhorio-invite:$code')).bytes.first;

class Invite {
  final String code, building, role;
  final String? tenantId, name, usedBy;
  final DateTime createdAt, expiresAt;
  final bool cancelled;
  Invite.fromRow(DbRow r)
      : code = r['code'] as String,
        building = r['building_id'] as String,
        role = r['role'] as String,
        tenantId = r['tenant_id'] as String?,
        name = r['name'] as String?,
        usedBy = r['used_by'] as String?,
        createdAt = DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        expiresAt = DateTime.fromMillisecondsSinceEpoch(r['expires_at'] as int),
        cancelled = r['cancelled'] == 1;
}

class JoinResult {
  final String building, buildingName, role;
  JoinResult(this.building, this.buildingName, this.role);
}

/// Why a join failed: invalid | expired | used | notFound | self | timeout.
class JoinError implements Exception {
  final String reason;
  JoinError(this.reason);
  @override
  String toString() => 'JoinError($reason)';
}

class Invites extends ChangeNotifier {
  final ZxStore store;
  final Ledger ledger;
  final SyncEngine engine;

  /// The tags to announce changed.
  void Function(Set<int> tags)? onTags;

  /// Pubkeys of the nodes announcing [tag].
  Iterable<String> Function(int tag) peersWithTag;

  /// Called while searching for an inviter (e.g. to announce ourselves, which
  /// makes the other nodes answer with their announces).
  void Function()? onSearch;

  DateTime Function() now = DateTime.now;
  final _random = Random.secure();
  int _wrong = 0;
  Future<void> _lock = Future.value();

  Invites(this.store, this.ledger, this.engine, {required this.peersWithTag}) {
    engine.onInvite = _onMessage;
  }

  // ------------------------------------------------------------ inviter side

  /// Makes a code for [building] giving [role] (a tenant: [tenantId]).
  Future<Invite> create(String building, Role role, {String? tenantId, String? name}) async {
    final mine = await ledger.myRole(building);
    if (mine == null || !mine.canGrant.contains(role)) {
      throw StateError('not allowed to invite a ${role.name} here');
    }
    String code;
    do {
      code = List.generate(inviteLength, (_) => inviteAlphabet[_random.nextInt(inviteAlphabet.length)]).join();
    } while (await store.scalar('SELECT 1 FROM invites WHERE code = ?', [code]) != null);
    final t = now();
    await store.exec(
        'INSERT INTO invites (code, building_id, role, tenant_id, name, created_at, expires_at, cancelled) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 0)',
        [code, building, role.name, tenantId, name, t.millisecondsSinceEpoch,
          t.add(inviteLifetime).millisecondsSinceEpoch]);
    _wrong = 0;
    await refreshTags();
    notifyListeners();
    return (await _byCode(code))!;
  }

  Future<Invite?> _byCode(String code) async {
    final r = await store.first('SELECT * FROM invites WHERE code = ?', [code]);
    return r == null ? null : Invite.fromRow(r);
  }

  /// Codes still usable (of [building], or all).
  Future<List<Invite>> active({String? building}) async {
    final rows = await store.query(
        'SELECT * FROM invites WHERE used_by IS NULL AND cancelled = 0 AND expires_at > ? '
        '${building == null ? '' : 'AND building_id = ? '}ORDER BY created_at DESC',
        [now().millisecondsSinceEpoch, ?building]);
    return rows.map(Invite.fromRow).toList();
  }

  Future<void> cancel(String code) async {
    await store.exec('UPDATE invites SET cancelled = 1 WHERE code = ?', [code]);
    await refreshTags();
    notifyListeners();
  }

  /// Tells the node which tags to announce (call now and then: codes expire).
  Future<Set<int>> refreshTags() async {
    final tags = {for (final i in await active()) inviteTag(i.code)};
    onTags?.call(tags);
    return tags;
  }

  Future<void> _onMessage(String from, Map<String, Object?> msg) async {
    switch (msg['t']) {
      case 'join':
        final prev = _lock;
        final done = Completer<void>();
        _lock = done.future;
        try {
          await prev;
          await _onJoin(from, msg);
        } finally {
          done.complete();
        }
      case 'join-ok' || 'join-fail':
        _onReply(from, msg);
    }
  }

  Future<void> _onJoin(String from, Map<String, Object?> msg) async {
    Future<void> fail(String reason) => engine.post(from, {'t': 'join-fail', 'reason': reason});
    final code = normalizeInviteCode(msg['code'] as String? ?? '');
    final inv = code == null ? null : await _byCode(code);
    if (inv == null || inv.cancelled) {
      if (++_wrong >= maxWrongCodes) {
        await store.exec('UPDATE invites SET cancelled = 1 WHERE used_by IS NULL AND cancelled = 0');
        await refreshTags();
        notifyListeners();
      }
      return fail('invalid');
    }
    final b = await store.first('SELECT name FROM buildings WHERE id = ?', [inv.building]);
    Future<void> ok() => engine.post(from,
        {'t': 'join-ok', 'b': inv.building, 'name': b?['name'], 'role': inv.role});
    // Our answer got lost: say it again.
    if (inv.usedBy == from) return ok();
    if (inv.usedBy != null) return fail('used');
    if (!inv.expiresAt.isAfter(now())) return fail('expired');
    if (from == ledger.me) return fail('self');
    final mine = await ledger.myRole(inv.building);
    final role = roleOf(inv.role)!;
    if (mine == null || !mine.canGrant.contains(role)) return fail('invalid');
    try {
      await ledger.upsert('members', inv.building, {
        'pubkey': from,
        'role': role.name,
        'name': inv.name,
        'tenant_id': inv.tenantId,
        'deleted': 0,
      }, id: '${inv.building}:$from');
    } catch (_) {
      return fail('invalid');
    }
    await store.exec('UPDATE invites SET used_by = ?, used_at = ? WHERE code = ?',
        [from, now().millisecondsSinceEpoch, inv.code]);
    await refreshTags();
    notifyListeners();
    await ok();
  }

  // ------------------------------------------------------------- joiner side

  _Join? _join;

  void _onReply(String from, Map<String, Object?> msg) {
    final j = _join;
    if (j == null || !j.asked.contains(from) || j.done.isCompleted) return;
    if (msg['t'] == 'join-ok') {
      j.done.complete(JoinResult(msg['b'] as String, msg['name'] as String? ?? '',
          msg['role'] as String? ?? 'user'));
    } else {
      j.failures[from] = msg['reason'] as String? ?? 'invalid';
    }
  }

  /// Finds whoever announces the tag of [code] and asks to join. The
  /// building's data then arrives by the normal sync.
  Future<JoinResult> join(String code,
      {Duration timeout = const Duration(minutes: 2),
      Duration failAfter = const Duration(seconds: 20)}) async {
    final c = normalizeInviteCode(code);
    if (c == null) throw JoinError('invalid');
    if (_join != null && !_join!.done.isCompleted) throw JoinError('busy');
    final j = _join = _Join();
    try {
      final tag = inviteTag(c);
      final start = now();
      onSearch?.call();
      var round = 0;
      while (!j.done.isCompleted) {
        for (final pk in peersWithTag(tag)) {
          if (pk == ledger.me || !j.asked.add(pk)) continue;
          unawaited(engine.post(pk, {'t': 'join', 'code': c}));
        }
        final waited = now().difference(start);
        // Everyone asked said no, and we searched long enough for others.
        if (j.asked.isNotEmpty &&
            j.failures.length == j.asked.length &&
            waited >= failAfter) {
          throw JoinError(_worst(j.failures.values));
        }
        if (waited >= timeout) {
          throw JoinError(j.failures.isEmpty ? (j.asked.isEmpty ? 'notFound' : 'timeout') : _worst(j.failures.values));
        }
        // Re-announce now and then so inviters that missed us answer.
        if (++round % 10 == 0) onSearch?.call();
        await Future.any([j.done.future, Future<void>.delayed(const Duration(seconds: 2))]);
      }
      return await j.done.future;
    } finally {
      _join = null;
    }
  }

  static String _worst(Iterable<String> reasons) {
    for (final r in ['used', 'expired', 'self']) {
      if (reasons.contains(r)) return r;
    }
    return 'invalid';
  }
}

class _Join {
  final asked = <String>{};
  final failures = <String, String>{};
  final done = Completer<JoinResult>();
}
