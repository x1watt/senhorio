// Bills split between tenants (the energy of an apartment...).

/// [total] cents in [n] parts that add up exactly: the first parts carry
/// the remainder cent.
List<int> splitEvenly(int total, int n) {
  if (n <= 0) return const [];
  final base = total ~/ n, rest = total - base * n;
  return [for (var i = 0; i < n; i++) base + (i < rest ? 1 : 0)];
}

/// A tenant's share still to pay (or to confirm) past its due date.
bool shareOverdue(Map<String, Object?> share, Map<String, Object?> bill, String today) =>
    share['status'] != 'confirmed' &&
    (bill['due_date'] as String? ?? '').isNotEmpty &&
    (bill['due_date'] as String).compareTo(today) < 0;
