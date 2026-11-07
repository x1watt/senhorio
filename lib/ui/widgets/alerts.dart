// The permanent in-app warning for a tenant: late rent and unpaid shared
// bills, per building (or for one building).

import 'package:flutter/material.dart';

import '../../domain/alerts.dart';
import 'common.dart';

class TenantAlertsBanner extends StatelessWidget {
  final String? building; // only this building's alert
  const TenantAlertsBanner({super.key, this.building});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return LiveFuture<List<TenantAlert>>(
      load: (a) => tenantAlerts(a.q, a.ledger),
      builder: (context, alerts) {
        final list = building == null ? alerts : alerts.where((a) => a.building == building).toList();
        if (list.isEmpty) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Card(
          color: scheme.errorContainer,
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Text(l.paymentsOverdue,
                    style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.bold)),
              ]),
              for (final a in list) ...[
                if (building == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(a.buildingName, style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600)),
                  ),
                if (a.lateRentCents > 0)
                  Text(l.rentLateLine(context.money(a.lateRentCents), a.latePeriods),
                      style: TextStyle(color: scheme.onErrorContainer)),
                for (final b in a.overdueBills)
                  Text(l.billLateLine(b['title'] as String? ?? '', context.money(b['share_cents'] as int), b['due_date'] as String? ?? ''),
                      style: TextStyle(color: scheme.onErrorContainer)),
              ],
              const SizedBox(height: 6),
              Text(l.overdueHelp, style: TextStyle(color: scheme.onErrorContainer, fontSize: 12)),
            ]),
          ),
        );
      },
    );
  }
}
