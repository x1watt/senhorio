// The user's NOSTR identity (nsec/npub) and the secrets kept beside it.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:reticulum/reticulum.dart' show NostrCrypto, NostrEvent;

import '../core/ids.dart';

/// Where secrets live. The default is the OS keystore; tests use memory.
abstract class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryKeyStore implements KeyStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
}

/// Android Keystore / OS keychain, falling back to a 0600 file in [fallbackDir]
/// when the platform has no keyring (headless Linux without libsecret).
class SecureKeyStore implements KeyStore {
  final String fallbackDir;
  final _secure = const FlutterSecureStorage();
  bool _useFile = false;

  SecureKeyStore(this.fallbackDir);

  File _file(String key) => File('$fallbackDir/.$key.secret');

  @override
  Future<String?> read(String key) async {
    if (!_useFile) {
      try {
        final v = await _secure.read(key: key);
        if (v != null) return v;
      } catch (_) {
        _useFile = true;
      }
    }
    final f = _file(key);
    return await f.exists() ? (await f.readAsString()).trim() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_useFile) {
      try {
        await _secure.write(key: key, value: value);
        return;
      } catch (_) {
        _useFile = true;
      }
    }
    final f = _file(key);
    await f.writeAsString(value, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', f.path]);
    }
  }
}

class Identity {
  final String privateKeyHex;
  final String pubkey; // hex, x-only

  Identity(this.privateKeyHex) : pubkey = NostrCrypto.derivePublicKey(privateKeyHex);

  String get npub => NostrCrypto.encodeNpub(pubkey);
  String get nsec => NostrCrypto.encodeNsec(privateKeyHex);

  void sign(NostrEvent e) => e.sign(privateKeyHex);

  static Identity generate() =>
      Identity(NostrCrypto.generateKeyPair().privateKeyHex);

  /// Accepts nsec1… or 64 hex chars.
  static Identity parse(String secret) {
    final s = secret.trim();
    if (s.startsWith('nsec1')) return Identity(NostrCrypto.decodeNsec(s));
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(s)) return Identity(s.toLowerCase());
    throw const FormatException('not an nsec');
  }
}

/// Accepts npub1… or 64 hex chars; returns the hex pubkey.
String parsePubkey(String input) {
  final s = input.trim();
  if (s.startsWith('npub1')) return NostrCrypto.decodeNpub(s);
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(s)) return s.toLowerCase();
  throw const FormatException('not an npub');
}

String shortNpub(String pubkeyHex) {
  final n = NostrCrypto.encodeNpub(pubkeyHex);
  return '${n.substring(0, 12)}…${n.substring(n.length - 6)}';
}

class IdentityService {
  static const _kNsec = 'senhorio_nsec';
  static const _kDbPassword = 'senhorio_db_password';
  final KeyStore store;
  late Identity identity;

  IdentityService(this.store);

  /// Loads the identity, creating one on first run.
  Future<Identity> load() async {
    final s = await store.read(_kNsec);
    if (s != null && s.isNotEmpty) {
      identity = Identity.parse(s);
    } else {
      identity = Identity.generate();
      await store.write(_kNsec, identity.nsec);
    }
    return identity;
  }

  /// Replaces the identity with an imported nsec.
  Future<Identity> import(String nsec) async {
    final id = Identity.parse(nsec);
    await store.write(_kNsec, id.nsec);
    identity = id;
    return id;
  }

  /// Password of the local archive (random, kept in the keystore).
  Future<String> dbPassword() async {
    var p = await store.read(_kDbPassword);
    if (p == null || p.isEmpty) {
      p = hexOf(randomBytes(32));
      await store.write(_kDbPassword, p);
    }
    return p;
  }
}
