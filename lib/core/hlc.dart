// Hybrid logical clock: timestamps that sort lexicographically, never go
// backwards on one device and move past every timestamp seen from peers.
// Format: 13-digit ms since epoch, '-', 4-digit counter, '-', node id.

class Hlc implements Comparable<Hlc> {
  final int millis;
  final int counter;
  final String node;

  const Hlc(this.millis, this.counter, this.node);

  static const zero = Hlc(0, 0, '0');

  static Hlc parse(String s) {
    final parts = s.split('-');
    if (parts.length < 3) return zero;
    return Hlc(int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
        parts.sublist(2).join('-'));
  }

  @override
  String toString() =>
      '${millis.toString().padLeft(13, '0')}-${counter.toString().padLeft(4, '0')}-$node';

  @override
  int compareTo(Hlc other) => toString().compareTo(other.toString());

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(millis);
}

/// Hands out [Hlc]s for one node.
class HlcClock {
  final String node;
  final int Function() _now;
  Hlc _last;

  HlcClock(this.node, {int Function()? now})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _last = Hlc(0, 0, node);

  /// A new timestamp, strictly greater than every one issued or observed.
  Hlc now() {
    final wall = _now();
    if (wall > _last.millis) {
      _last = Hlc(wall, 0, node);
    } else {
      _last = Hlc(_last.millis, _last.counter + 1, node);
    }
    return _last;
  }

  /// Moves the clock past a timestamp received from a peer.
  void observe(String remote) {
    final r = Hlc.parse(remote);
    final wall = _now();
    final m = [wall, _last.millis, r.millis].reduce((a, b) => a > b ? a : b);
    int c;
    if (m == _last.millis && m == r.millis) {
      c = (_last.counter > r.counter ? _last.counter : r.counter) + 1;
    } else if (m == _last.millis) {
      c = _last.counter + 1;
    } else if (m == r.millis) {
      c = r.counter + 1;
    } else {
      c = 0;
    }
    _last = Hlc(m, c, node);
  }
}
