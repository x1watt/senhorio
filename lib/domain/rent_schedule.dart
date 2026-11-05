// Which rent periods are paid, partly paid or late.

import '../core/dates.dart';
import '../data/zx_store.dart';
import 'recurrence.dart';

enum DueState { paid, partial, open, late }

class RentDue {
  final DateTime due;
  final int expected;
  final int paid;
  final DueState state;
  RentDue(this.due, this.expected, this.paid, this.state);

  String get period => isoDate(due);
  int get owed => expected - paid > 0 ? expected - paid : 0;
}

class LeaseStatus {
  final DbRow lease;
  final List<RentDue> dues;
  LeaseStatus(this.lease, this.dues);

  Iterable<RentDue> get late => dues.where((d) => d.state == DueState.late);
  int get owedLate => late.fold(0, (a, d) => a + d.owed);
  bool get isLate => late.isNotEmpty;

  /// Oldest period not fully paid (the default for a new payment).
  RentDue? get firstUnpaid {
    for (final d in dues) {
      if (d.state != DueState.paid) return d;
    }
    return null;
  }
}

Recurrence recurrenceOfLease(DbRow lease) => Recurrence(
      frequencyOf(lease['frequency']),
      (lease['due_day'] as int?) ?? 1,
      parseIsoDate(lease['start_date']) ?? DateTime.now(),
      parseIsoDate(lease['end_date']),
    );

/// Rent periods of [lease] up to [today], matched with [payments] (rows of
/// `payments` for this lease). Payments without a matching period, or
/// beyond what a period needs, fill the oldest open periods.
LeaseStatus leaseStatus(DbRow lease, List<DbRow> payments, DateTime today) {
  final rent = (lease['rent_cents'] as int?) ?? 0;
  final grace = (lease['grace_days'] as int?) ?? 0;
  final rec = recurrenceOfLease(lease);
  // Include the next period so "open" (not yet late) shows up.
  final dates = rec.dueDates(today.add(Duration(days: grace)));
  final paidBy = <String, int>{};
  var loose = 0;
  final periods = {for (final d in dates) isoDate(d)};
  for (final p in payments) {
    final amt = (p['amount_cents'] as int?) ?? 0;
    final per = p['period'] as String?;
    if (per != null && periods.contains(per)) {
      paidBy[per] = (paidBy[per] ?? 0) + amt;
    } else {
      loose += amt;
    }
  }
  // Overpayment of a period carries to the oldest open ones.
  for (final k in periods) {
    final over = (paidBy[k] ?? 0) - rent;
    if (over > 0) {
      paidBy[k] = rent;
      loose += over;
    }
  }
  final dues = <RentDue>[];
  final t = dateOnly(today);
  for (final d in dates) {
    final k = isoDate(d);
    var paid = paidBy[k] ?? 0;
    if (paid < rent && loose > 0) {
      final take = (rent - paid) < loose ? rent - paid : loose;
      paid += take;
      loose -= take;
    }
    DueState st;
    if (paid >= rent) {
      st = DueState.paid;
    } else if (t.isAfter(d.add(Duration(days: grace)))) {
      st = DueState.late;
    } else {
      st = paid > 0 ? DueState.partial : DueState.open;
    }
    dues.add(RentDue(d, rent, paid, st));
  }
  return LeaseStatus(lease, dues);
}
