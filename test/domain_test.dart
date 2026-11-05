import 'package:flutter_test/flutter_test.dart';
import 'package:senhorio/core/hlc.dart';
import 'package:senhorio/core/money.dart';
import 'package:senhorio/domain/category_learner.dart';
import 'package:senhorio/domain/recurrence.dart';
import 'package:senhorio/domain/rent_schedule.dart';
import 'package:senhorio/domain/stats.dart';

void main() {
  group('recurrence', () {
    test('monthly clamps to month end', () {
      final r = Recurrence(Frequency.monthly, 31, DateTime(2026, 1, 1));
      expect(r.dueDates(DateTime(2026, 4, 30)).map((d) => '${d.month}-${d.day}'),
          ['1-31', '2-28', '3-31', '4-30']);
    });
    test('start after due day: first due on start, then on due day', () {
      final r = Recurrence(Frequency.monthly, 1, DateTime(2026, 1, 15));
      expect(r.dueDates(DateTime(2026, 3, 1)),
          [DateTime(2026, 1, 15), DateTime(2026, 2, 1), DateTime(2026, 3, 1)]);
    });
    test('weekly on weekday', () {
      final r = Recurrence(Frequency.weekly, 1, DateTime(2026, 11, 4)); // Wednesday
      expect(r.dueDates(DateTime(2026, 11, 20)).first, DateTime(2026, 11, 9));
      expect(r.dueDates(DateTime(2026, 11, 20)).length, 2);
    });
    test('end date stops the series; nextDue', () {
      final r = Recurrence(Frequency.monthly, 5, DateTime(2026, 1, 1), DateTime(2026, 2, 10));
      expect(r.dueDates(DateTime(2026, 12, 1)).length, 2);
      expect(Recurrence(Frequency.quarterly, 5, DateTime(2026, 1, 1)).nextDue(DateTime(2026, 1, 5)),
          DateTime(2026, 4, 5));
    });
  });

  group('rent schedule', () {
    final lease = {
      'id': 'L', 'rent_cents': 50000, 'frequency': 'monthly', 'due_day': 8,
      'start_date': '2026-01-01', 'grace_days': 3,
    };
    test('late, partial, overpayment carry', () {
      final st = leaseStatus(lease, [
        {'period': '2026-01-08', 'amount_cents': 50000},
        {'period': '2026-02-08', 'amount_cents': 20000},
      ], DateTime(2026, 3, 20));
      expect(st.dues.map((d) => d.state),
          [DueState.paid, DueState.late, DueState.late]);
      expect(st.owedLate, 30000 + 50000);
      // an overpayment on January fills February
      final st2 = leaseStatus(lease, [
        {'period': '2026-01-08', 'amount_cents': 100000},
      ], DateTime(2026, 2, 20));
      expect(st2.dues.map((d) => d.state), [DueState.paid, DueState.paid]);
    });
    test('grace days keep a fresh period open', () {
      final st = leaseStatus(lease, [
        {'period': '2026-01-08', 'amount_cents': 50000},
      ], DateTime(2026, 2, 10));
      expect(st.dues.last.state, DueState.open);
      expect(st.isLate, isFalse);
    });
  });

  group('category learner', () {
    final ids = {for (final k in categoryKeywords.keys) k: 'cat_$k'};
    test('keyword priors work from day one', () {
      final l = CategoryLearner(ids);
      expect(l.suggest(const ExpenseFeatures(vendor: 'EDP Comercial', amountCents: 4500)).first.categoryId,
          'cat_energy');
      expect(l.suggest(const ExpenseFeatures(vendor: 'Águas do Porto')).first.categoryId, 'cat_water');
    });
    test('learns vendors and recurring amounts', () {
      final l = CategoryLearner(ids);
      for (var i = 0; i < 3; i++) {
        l.learn(const ExpenseFeatures(vendor: 'Sr. Joaquim', amountCents: 8000), 'cat_repairs');
        l.learn(const ExpenseFeatures(vendor: 'Casa Silva', description: 'lâmpadas', amountCents: 1200), 'cat_material');
      }
      final s = l.suggest(const ExpenseFeatures(vendor: 'Sr. Joaquim', amountCents: 8500));
      expect(s.first.categoryId, 'cat_repairs');
      expect(s.first.recurring, isTrue);
      expect(l.suggest(const ExpenseFeatures(description: 'lampadas led')).first.categoryId, 'cat_material');
    });
  });

  test('hlc is monotonic and moves past remote clocks', () {
    var t = 1000;
    final c = HlcClock('a', now: () => t);
    final a = c.now();
    final b = c.now();
    expect(b.compareTo(a), greaterThan(0));
    c.observe(const Hlc(5000, 3, 'b').toString());
    t = 1001;
    expect(c.now().compareTo(const Hlc(5000, 3, 'b')), greaterThan(0));
  });

  test('money parsing', () {
    expect(parseMoney('12'), 1200);
    expect(parseMoney('12,5'), 1250);
    expect(parseMoney('1.234,56'), 123456);
    expect(parseMoney('1,234.56'), 123456);
    expect(parseMoney('€ 3.10'), 310);
    expect(parseMoney('abc'), isNull);
  });

  test('stats', () {
    final months = monthKeys(DateTime(2026, 3, 15), 3);
    expect(months, ['2026-01', '2026-02', '2026-03']);
    final t = monthlyTotals([
      {'paid_on': '2026-02-03', 'amount_cents': 500},
    ], [
      {'date': '2026-02-10', 'amount_cents': 200, 'category_id': 'x', 'quantity': 10},
      {'date': '2025-02-10', 'amount_cents': 999, 'category_id': 'x'},
    ], months);
    expect(t[1].net, 300);
    final u = utilitySeries([
      {'date': '2026-02-10', 'amount_cents': 200, 'category_id': 'x', 'quantity': 10.0},
    ], 'x', months);
    expect(u[1].unitCost, 20);
    final occ = occupancy([
      {'id': 'r1', 'available': 1}, {'id': 'r2', 'available': 1}, {'id': 'r3', 'available': 0},
    ], [
      {'room_id': 'r1', 'start_date': '2026-01-01'},
    ], DateTime(2026, 3, 1));
    expect((occ.rooms, occ.rented), (2, 1));
  });
}
