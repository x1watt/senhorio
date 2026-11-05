// The Reticulum node: TCP uplinks to every public hub (a mesh, see
// reticulum-dart doc/peer-discovery.md) plus LAN discovery, a "senhorio/sync"
// announce that binds our NOSTR npub to our Reticulum identity, and LXMF
// (end-to-end encrypted, over links) to carry the sync messages.
//
// Patterns copied from xprs (app/lib/services/reticulum/rns_autostart.dart
// and core rns_service.dart): hub list, mesh + reconnect loop, inbound
// dispatch (LXMF first, everything else to the transport engine).

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:reticulum/reticulum.dart' hide debugPrint;

import '../core/ids.dart';
import '../identity/identity_service.dart';

const kSyncApp = 'senhorio';
const kSyncAspects = ['sync'];
const kSyncTitle = 'senhorio/1';

/// Public hubs (from xprs preferences_service.dart, rns.bootstrapServers).
const defaultHubs = [
  'rns.wisco.network:4242',
  'sydney.reticulum.au:4242',
  'rns.birdsnet.com.br:4242',
  'use.inertia.chat:4242',
];

const _lanPort = 42671;

class PeerInfo {
  final String pubkey;
  final RnsIdentity identity;
  final Uint8List lxmfDest;
  DateTime lastSeen;
  String via;
  PeerInfo(this.pubkey, this.identity, this.lxmfDest, this.lastSeen, this.via);
}

class RnsNode extends ChangeNotifier {
  final Identity nostr;
  final KeyStore keys;
  List<String> hubs;
  final void Function(String pubkey, Map<String, Object?> msg) onMessage;
  final void Function(String pubkey) onPeer;

  RnsTransportClient? _transport;
  RnsIdentity? _id;
  LxmfRouter? _lxmf;
  final _tcp = <String, RnsTcpInterface>{};
  RnsLanInterface? _lan;
  Timer? _tick;
  DateTime _lastAnnounce = DateTime.fromMillisecondsSinceEpoch(0);
  /// Known nodes by "pubkey/rnsHash": one npub may run on several devices.
  final peers = <String, PeerInfo>{};

  Iterable<PeerInfo> peersOf(String pubkey) => peers.values.where((p) => p.pubkey == pubkey);
  bool knows(String pubkey) => peers.values.any((p) => p.pubkey == pubkey);
  final _byLxmf = <String, String>{}; // lxmf dest hex -> pubkey
  final logLines = <String>[];
  bool running = false;
  final _seen = <String>{};

  /// Announce names never shed by the transport's flood budget.
  static List<String> get priorityNames => [
        hexOf(RnsDestination.nameHash(kSyncApp, kSyncAspects)),
        hexOf(RnsDestination.nameHash(kLxmfApp, kLxmfDeliveryAspects)),
      ];

  /// Logs the transport engine too (debugging).
  static bool verbose = false;

  RnsNode({
    required this.nostr,
    required this.keys,
    required this.onMessage,
    required this.onPeer,
    this.hubs = defaultHubs,
  });

  Iterable<String> get connectedHubs => _tcp.entries.where((e) => e.value.isConnected).map((e) => e.key);
  bool get lanUp => _lan != null;
  String? get rnsHash => _id?.hexHash;

  void log(String s) {
    final line = '${DateTime.now().toIso8601String().substring(11, 19)} $s';
    logLines.add(line);
    if (logLines.length > 300) logLines.removeAt(0);
    debugPrint('RNS $s');
    notifyListeners();
  }

  // ---------------------------------------------------------------- lifecycle

  Future<void> start() async {
    if (running) return;
    running = true;
    _id = await _loadIdentity();
    final t = await RnsTransportClient.spawn(log: verbose ? (m) => log('tx: $m') : null);
    _transport = t;
    t.onAnnounce = _onAnnounce;
    t.onPathRequest = (h) {
      if (_isOurs(h)) unawaited(announce(force: true));
    };
    t.setPriorityAnnounceNames(priorityNames);
    _lxmf = LxmfRouter(
      identity: _id!,
      send: (raw) => _transport?.sendLinkAware(raw),
      nextHopFor: (peer) => _transport?.nextHopForIdentity(peer),
      identityForDest: (h) => _transport?.pathFor(h)?.identity ?? _identityForLxmf(h),
      requestPath: (h) => _transport?.requestPath(h),
      onMessage: _onLxmf,
      log: verbose ? (m) => log('lxmf: $m') : null,
    );
    await _bindLan();
    await _connectHubs();
    await announce(force: true);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => tick());
    log('node up, rns ${_id!.hexHash.substring(0, 12)}');
  }

  Future<void> stop() async {
    running = false;
    _tick?.cancel();
    _reannounce?.cancel();
    for (final i in _tcp.values) {
      await i.close();
    }
    _tcp.clear();
    await _lan?.close();
    _lan = null;
    _transport?.close();
    _transport = null;
    notifyListeners();
  }

  Future<RnsIdentity> _loadIdentity() async {
    final s = await keys.read('senhorio_rns_identity');
    if (s != null && s.length == 128) return RnsIdentity.fromPrivateKey(bytesOfHex(s));
    final id = await RnsIdentity.generate();
    await keys.write('senhorio_rns_identity', hexOf(id.getPrivateKey()!));
    return id;
  }

  Future<void> _bindLan() async {
    try {
      final lan = RnsLanInterface(port: _lanPort, onPacket: (raw) => _onInbound(raw, 'lan'));
      await lan.bind();
      _transport!.addInterface(lan);
      _lan = lan;
    } catch (e) {
      log('lan: $e');
    }
  }

  Future<void> _connectHubs() async {
    for (final h in hubs) {
      final cur = _tcp[h];
      if (cur != null && cur.isConnected) continue;
      if (cur != null) {
        _transport?.removeInterface(cur);
        _tcp.remove(h);
      }
      final parts = h.split(':');
      final host = parts.first;
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 4242 : 4242;
      final label = 'tcp:$host:$port';
      final iface = RnsTcpInterface(
        host: host,
        port: port,
        label: label,
        uplink: true,
        onPacket: (raw) => _onInbound(raw, label),
        onDisconnect: () {
          log('hub down $h');
          notifyListeners();
        },
      );
      try {
        await iface.connect(timeout: const Duration(seconds: 8));
        _transport?.addInterface(iface);
        _tcp[h] = iface;
        log('hub up $h');
      } catch (e) {
        log('hub $h unreachable');
      }
    }
    notifyListeners();
  }

  /// Reconnects dropped hubs and re-announces when due (also driven by the
  /// Android service's heartbeat while in the background).
  Future<void> tick() async {
    if (!running) return;
    await _connectHubs();
    await announce();
  }

  // ---------------------------------------------------------------- announce

  bool _isOurs(Uint8List h) {
    final id = _id;
    if (id == null) return false;
    return _eq(h, RnsDestination.hash(id, kSyncApp, kSyncAspects)) ||
        _eq(h, RnsDestination.hash(id, kLxmfApp, kLxmfDeliveryAspects));
  }

  /// appData = npub pubkey (32) || schnorr(sha256("senhorio-bind" || rns hash)) (64)
  Uint8List _bindingAppData() {
    final pk = bytesOfHex(nostr.pubkey);
    final sig = bytesOfHex(NostrCrypto.schnorrSign(_bindDigest(_id!.hash), nostr.privateKeyHex));
    return Uint8List.fromList([...pk, ...sig]);
  }

  static String _bindDigest(Uint8List rnsHash) =>
      sha256.convert([...utf8.encode('senhorio-bind'), ...rnsHash]).toString();

  /// Announces the sync and LXMF destinations (at most every 5 minutes
  /// unless [force]).
  Future<void> announce({bool force = false}) async {
    final t = _transport;
    final id = _id;
    if (t == null || id == null) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastAnnounce) < const Duration(minutes: 5)) return;
    _lastAnnounce = now;
    final a = await RnsAnnounceBuilder.build(id, kSyncApp, kSyncAspects, appData: _bindingAppData());
    t.sendAnnounce(a.pack(), a.destHash);
    final lx = await RnsAnnounceBuilder.build(id, kLxmfApp, kLxmfDeliveryAspects,
        appData: Uint8List.fromList(utf8.encode('senhorio')));
    t.sendAnnounce(lx.pack(), lx.destHash);
  }

  Timer? _reannounce;

  /// One forced announce, at least 5 s after the previous one.
  void _reannounceSoon() {
    if (_reannounce?.isActive ?? false) return;
    final since = DateTime.now().difference(_lastAnnounce);
    const gap = Duration(seconds: 5);
    _reannounce = Timer(since >= gap ? Duration.zero : gap - since, () => announce(force: true));
  }

  void _onAnnounce(RnsAnnounce ann, int hops, String via) {
    final id = _id;
    if (id == null || _eq(ann.identity.hash, id.hash)) return;
    if (!_eq(ann.destHash, RnsDestination.hash(ann.identity, kSyncApp, kSyncAspects))) return;
    final ad = ann.appData;
    if (ad.length != 96) return;
    final pk = hexOf(ad.sublist(0, 32));
    final sig = hexOf(ad.sublist(32, 96));
    bool ok;
    try {
      ok = NostrCrypto.schnorrVerify(_bindDigest(ann.identity.hash), sig, pk);
    } catch (_) {
      ok = false;
    }
    if (!ok) return;
    final lx = RnsDestination.hash(ann.identity, kLxmfApp, kLxmfDeliveryAspects);
    final key = '$pk/${ann.identity.hexHash}';
    final known = peers[key];
    peers[key] = PeerInfo(pk, ann.identity, lx, DateTime.now(), via);
    _byLxmf[hexOf(lx)] = pk;
    if (known == null) {
      log('peer ${shortNpub(pk)} via $via');
      // A newcomer missed our last announce: answer so it learns us now.
      _reannounceSoon();
    }
    notifyListeners();
    onPeer(pk);
  }

  RnsIdentity? _identityForLxmf(Uint8List h) {
    final pk = _byLxmf[hexOf(h)];
    return pk == null ? null : peers.values.where((p) => p.pubkey == pk && hexOf(p.lxmfDest) == hexOf(h)).firstOrNull?.identity;
  }

  // ---------------------------------------------------------------- traffic

  Future<void> _onInbound(Uint8List raw, String via) async {
    final p = RnsPacket.parse(raw);
    if (verbose) log('rx ${raw.length}B via $via type ${p?.packetType}');
    if (p == null) return;
    if (p.destType == RnsDestType.link) _transport?.noteLinkIface(p.destHash, via);
    if (p.packetType != RnsPacketType.announce) {
      try {
        if (await _lxmf?.handlePacket(p) ?? false) return;
      } catch (e) {
        log('lxmf: $e');
        return;
      }
    }
    _transport?.ingestRaw(raw, via);
  }

  void _onLxmf(LxmfMessage m) {
    if (m.titleString != kSyncTitle) return;
    final key = hexOf(m.hash);
    if (!_seen.add(key)) return;
    if (_seen.length > 2048) _seen.remove(_seen.first);
    // sourceHash is the sender's LXMF delivery destination.
    final pk = _byLxmf[hexOf(m.sourceHash)];
    if (pk == null) {
      log('message from an unknown node dropped');
      return;
    }
    try {
      final msg = (jsonDecode(m.contentString) as Map).cast<String, Object?>();
      onMessage(pk, msg);
    } catch (e) {
      log('bad message: $e');
    }
  }

  /// Sends [msg] to every device of NOSTR [pubkey] (encrypted LXMF over a
  /// link); true when at least one confirmed.
  Future<bool> send(String pubkey, Map<String, Object?> msg) async {
    final id = _id;
    if (id == null || _lxmf == null) return false;
    var ok = false;
    for (final p in peersOf(pubkey).toList()) {
      final m = await LxmfMessage.create(
        destinationHash: p.lxmfDest,
        source: id,
        title: kSyncTitle,
        content: jsonEncode(msg),
      );
      final r = await _lxmf!.deliver(m, timeout: const Duration(seconds: 60));
      if (r == LxmfDelivery.confirmed) {
        ok = true;
      } else {
        log('send to ${shortNpub(pubkey)} (${p.identity.hexHash.substring(0, 8)}): ${r.name}');
      }
    }
    return ok;
  }

  static bool _eq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
