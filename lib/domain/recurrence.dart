// Recurring due dates, shared by leases (rent) and recurring bills.

import '../core/dates.dart';

enum Frequency { weekly, monthly, quarterly, yearly }

Frequency frequencyOf(Object? s) => Frequency.values
    .firstWhere((f) => f.name == s, orElse: () => Frequency.monthly);

class Recurrence {
  final Frequency frequency;

  /// Day of month (1..31, clamped to the month's length) for monthly,
  /// quarterly and yearly; weekday (1 = Monday .. 7) for weekly.
  final int dueDay;
  final DateTime start;
  final DateTime? end;

  Recurrence(this.frequency, this.dueDay, DateTime start, [DateTime? end])
      : start = dateOnly(start),
        end = end == null ? null : dateOnly(end);

  /// Due dates from [start] up to and including [until] (and [end]).
  List<DateTime> dueDates(DateTime until) {
    final last = dateOnly(end != null && end!.isBefore(until) ? end! : until);
    final out = <DateTime>[];
    var d = _first();
    var i = 0;
    while (!d.isAfter(last) && i < 5000) {
      out.add(d);
      d = _next(d, ++i);
    }
    return out;
  }

  /// The first due date strictly after [after].
  DateTime nextDue(DateTime after) {
    var d = _first();
    var i = 0;
    while (!d.isAfter(dateOnly(after)) && i < 5000) {
      d = _next(d, ++i);
    }
    return d;
  }

  DateTime _first() {
    switch (frequency) {
      case Frequency.weekly:
        final wd = dueDay.clamp(1, 7);
        final delta = (wd - start.weekday) % 7;
        return start.add(Duration(days: delta));
      case Frequency.monthly:
      case Frequency.quarterly:
      case Frequency.yearly:
        final d = _clamped(start.year, start.month);
        // A lease starting after the due day owes from that start month
        // (first rent is due on the start day itself).
        return d.isBefore(start) ? start : d;
    }
  }

  DateTime _next(DateTime prev, int index) {
    switch (frequency) {
      case Frequency.weekly:
        return prev.add(const Duration(days: 7));
      case Frequency.monthly:
        return _monthsAfterStart(index);
      case Frequency.quarterly:
        return _monthsAfterStart(index * 3);
      case Frequency.yearly:
        return _monthsAfterStart(index * 12);
    }
  }

  DateTime _monthsAfterStart(int months) {
    final m = start.month - 1 + months;
    return _clamped(start.year + m ~/ 12, m % 12 + 1);
  }

  DateTime _clamped(int year, int month) =>
      DateTime(year, month, dueDay.clamp(1, daysInMonth(year, month)));
}
