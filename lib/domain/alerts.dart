// What a tenant owes right now: late rent and unpaid shares of bills past
// their due date. Shown as a permanent banner and, on Android, an ongoing
// notification.

import '../core/dates.dart';
import '../data/queries.dart';
import '../data/zx_store.dart';
import '../domain/roles.dart';
import '../data/ledger.dart';
import 'rent_schedule.dart';
import 'shared_bills.dart';

class TenantAlert {
  final String building, buildingName;
  final int lateRentCents, latePeriods;
  final List<DbRow> overdueBills; // shared_bills rows, with 'share_cents'
  TenantAlert(this.building, this.buildingName, this.lateRentCents, this.latePeriods, this.overdueBills);

  int get billsCents => overdueBills.fold(0, (a, b) => a + (b['share_cents'] as int));
  int get totalCents => lateRentCents + billsCents;
  bool get any => lateRentCents > 0 || overdueBills.isNotEmpty;
}

/// The alerts of every building where this identity is a tenant.
Future<List<TenantAlert>> tenantAlerts(Queries q, Ledger ledger, {DateTime? now}) async {
  final out = <TenantAlert>[];
  final t = now ?? DateTime.now();
  final today = isoDate(t);
  for (final b in await q.buildings()) {
    final bid = b['id'] as String;
    if (await ledger.myRole(bid) != Role.user) continue;
    final tid = await q.myTenantId(bid, ledger.me);
    if (tid == null) continue;
    var late = 0, periods = 0;
    for (final le in await q.leases(building: bid)) {
      if (le['tenant_id'] != tid) continue;
      final end = le['end_date'] as String?;
      if (end != null && end.compareTo(today) < 0) continue;
      final st = leaseStatus(le, await q.payments(lease: le['id'] as String), t);
      late += st.owedLate;
      periods += st.late.length;
    }
    final bills = <DbRow>[];
    for (final sh in await q.billShares(building: bid, tenant: tid)) {
      final bill = await q.byId('shared_bills', sh['bill_id'] as String);
      if (bill == null || bill['deleted'] == 1 || !shareOverdue(sh, bill, today)) continue;
      bills.add({...bill, 'share_cents': sh['amount_cents'] ?? 0, 'share_status': sh['status']});
    }
    final a = TenantAlert(bid, b['name'] as String? ?? '', late, periods, bills);
    if (a.any) out.add(a);
  }
  return out;
}
