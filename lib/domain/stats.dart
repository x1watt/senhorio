// Aggregations for the statistics screen (pure functions over rows).

import '../core/dates.dart';
import '../data/zx_store.dart';
import 'rent_schedule.dart';

class MonthTotals {
  final String month; // yyyy-mm
  int income = 0;
  int expenses = 0;
  MonthTotals(this.month);
  int get net => income - expenses;
}

/// The last [months] months ending with [until]'s month.
List<String> monthKeys(DateTime until, int months) => [
      for (var i = months - 1; i >= 0; i--) monthKey(DateTime(until.year, until.month - i, 1)),
    ];

List<MonthTotals> monthlyTotals(List<DbRow> payments, List<DbRow> expenses, List<String> months) {
  final m = {for (final k in months) k: MonthTotals(k)};
  for (final p in payments) {
    final k = (p['paid_on'] as String? ?? '').padRight(7).substring(0, 7);
    m[k]?.income += (p['amount_cents'] as int?) ?? 0;
  }
  for (final e in expenses) {
    final k = (e['date'] as String? ?? '').padRight(7).substring(0, 7);
    m[k]?.expenses += (e['amount_cents'] as int?) ?? 0;
  }
  return m.values.toList();
}

/// category id -> total, for expenses whose date starts with [prefix]
/// (a year "2026" or a month "2026-03"; empty = all).
Map<String, int> byCategory(List<DbRow> expenses, String prefix) {
  final out = <String, int>{};
  for (final e in expenses) {
    if (!(e['date'] as String? ?? '').startsWith(prefix)) continue;
    final c = (e['category_id'] as String?) ?? '';
    out[c] = (out[c] ?? 0) + ((e['amount_cents'] as int?) ?? 0);
  }
  return out;
}

class UtilityPoint {
  final String month;
  int cents = 0;
  double quantity = 0;
  UtilityPoint(this.month);
  /// Cost per unit of consumption, in cents (null without quantities).
  double? get unitCost => quantity > 0 ? cents / quantity : null;
}

/// Monthly cost and consumption of one category.
List<UtilityPoint> utilitySeries(List<DbRow> expenses, String categoryId, List<String> months) {
  final m = {for (final k in months) k: UtilityPoint(k)};
  for (final e in expenses) {
    if (e['category_id'] != categoryId) continue;
    final p = m[(e['date'] as String? ?? '').padRight(7).substring(0, 7)];
    if (p == null) continue;
    p.cents += (e['amount_cents'] as int?) ?? 0;
    p.quantity += ((e['quantity'] as num?) ?? 0).toDouble();
  }
  return m.values.toList();
}

class Occupancy {
  final int rooms; // rooms offered for rent
  final int rented;
  Occupancy(this.rooms, this.rented);
  double get rate => rooms == 0 ? 0 : rented / rooms;
}

Occupancy occupancy(List<DbRow> rooms, List<DbRow> leases, DateTime today) {
  final t = isoDate(today);
  final rentedRooms = {
    for (final le in leases)
      if ((le['start_date'] as String? ?? '').compareTo(t) <= 0 &&
          ((le['end_date'] as String?) == null || (le['end_date'] as String).compareTo(t) >= 0))
        le['room_id'],
  };
  final offered = rooms.where((r) => r['available'] != 0 || rentedRooms.contains(r['id'])).toList();
  return Occupancy(offered.length, offered.where((r) => rentedRooms.contains(r['id'])).length);
}

/// Share of the rent due in [year] (up to today) that has been paid.
({int expected, int paid}) collection(List<DbRow> leases, List<DbRow> payments, int year, DateTime today) {
  var expected = 0, paid = 0;
  for (final le in leases) {
    final st = leaseStatus(le, payments.where((p) => p['lease_id'] == le['id']).toList(), today);
    for (final d in st.dues) {
      if (d.due.year != year || d.due.isAfter(today)) continue;
      expected += d.expected;
      paid += d.paid;
    }
  }
  return (expected: expected, paid: paid);
}
