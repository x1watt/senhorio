import 'dart:math';
import 'dart:typed_data';

final _rnd = Random.secure();

/// Random 128-bit id as 32 lowercase hex chars.
String newId() => hexOf(randomBytes(16));

Uint8List randomBytes(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _rnd.nextInt(256)));

String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List bytesOfHex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
