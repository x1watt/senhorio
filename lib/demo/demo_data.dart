// Sample data for the browser preview (the web build keeps nothing between
// reloads, so it starts from this each time).

import 'dart:math';

import '../core/dates.dart';
import '../core/ids.dart';
import '../data/ledger.dart';
import '../domain/checkpoints.dart';
import '../identity/identity_service.dart';

typedef _C = ({String entity, String building, String id, String op, Map<String, Object?> fields});

Future<void> seedDemoData(Ledger ledger, Checkpoints checkpoints) async {
  final rnd = Random(7);
  final now = DateTime.now();
  DateTime monthsAgo(int m, int day) => DateTime(now.year, now.month - m, day);

  final b = await ledger.createBuilding({
    'name': 'Rua das Flores 12',
    'address': 'Rua das Flores 12, 4050-262 Porto',
    'currency': 'EUR',
  });
  final changes = <_C>[];
  String add(String entity, Map<String, Object?> fields) {
    final id = newId();
    changes.add((entity: entity, building: b, id: id, op: 'upsert', fields: fields));
    return id;
  }

  // A second owner of the accounting, to show the members tab.
  final partner = Identity.generate();
  changes.add((
    entity: 'members',
    building: b,
    id: '$b:${partner.pubkey}',
    op: 'upsert',
    fields: {'pubkey': partner.pubkey, 'name': 'Maria (sócia)', 'role': 'member'},
  ));

  final a1 = add('apartments', {'name': '1º Esquerdo', 'floor': '1'});
  final a2 = add('apartments', {'name': '2º Direito', 'floor': '2'});
  final rooms = [
    add('rooms', {'apartment_id': a1, 'name': 'Quarto A', 'area_m2': 12.5, 'available': 1}),
    add('rooms', {'apartment_id': a1, 'name': 'Quarto B', 'area_m2': 10.0, 'available': 1}),
    add('rooms', {'apartment_id': a1, 'name': 'Quarto C', 'area_m2': 9.0, 'available': 0}),
    add('rooms', {'apartment_id': a2, 'name': 'Suite', 'area_m2': 16.0, 'available': 1}),
    add('rooms', {'apartment_id': a2, 'name': 'Quarto D', 'area_m2': 11.0, 'available': 1}),
  ];
  final tenants = [
    add('tenants', {'name': 'Ana Ribeiro', 'phone': '912 345 678', 'email': 'ana@example.com',
        'emergency_contact': 'Rui Ribeiro (pai) 917 000 111', 'tax_id': '123456789'}),
    add('tenants', {'name': 'João Costa', 'phone': '934 111 222'}),
    add('tenants', {'name': 'Lena Müller', 'email': 'lena@example.com', 'notes': 'Erasmus'}),
    add('tenants', {'name': 'Pedro Santos', 'phone': '965 000 333'}),
  ];
  // room index, tenant index, rent (cents), months ago it started, months it paid
  final leases = [
    (0, 0, 42000, 6, 6),
    (1, 1, 38000, 5, 5),
    (3, 2, 52000, 6, 4), // two months late
    (4, 3, 40000, 2, 1), // one month late
  ];
  for (final (room, tenant, rent, start, paid) in leases) {
    final lease = add('leases', {
      'room_id': rooms[room],
      'tenant_id': tenants[tenant],
      'rent_cents': rent,
      'frequency': 'monthly',
      'due_day': 8,
      'start_date': isoDate(monthsAgo(start, 1)),
      'grace_days': 5,
      'deposit_cents': rent,
    });
    add('payments', {
      'lease_id': lease, 'kind': 'deposit', 'amount_cents': rent,
      'paid_on': isoDate(monthsAgo(start, 1)), 'method': 'Transferência',
    });
    for (var m = 0; m < paid; m++) {
      final due = monthsAgo(start - m, 8);
      add('payments', {
        'lease_id': lease,
        'period': isoDate(due),
        'amount_cents': rent,
        'paid_on': isoDate(due.add(Duration(days: rnd.nextInt(4)))),
        'method': m.isEven ? 'MB Way' : 'Transferência',
      });
    }
  }

  // Monthly utilities with consumption, plus a few one-off expenses.
  for (var m = 5; m >= 0; m--) {
    final kwh = 280 + rnd.nextInt(160) + (m >= 3 ? 90 : 0);
    add('expenses', {
      'category_id': 'cat_energy', 'vendor': 'EDP Comercial', 'description': 'Eletricidade',
      'amount_cents': (kwh * 21.5).round(), 'quantity': kwh.toDouble(), 'unit': 'kWh',
      'date': isoDate(monthsAgo(m, 12)), 'attachments': <String>[],
    });
    final m3 = 14 + rnd.nextInt(8);
    add('expenses', {
      'category_id': 'cat_water', 'vendor': 'Águas do Porto', 'description': 'Água e saneamento',
      'amount_cents': m3 * 290 + 850, 'quantity': m3.toDouble(), 'unit': 'm³',
      'date': isoDate(monthsAgo(m, 18)), 'attachments': <String>[],
    });
    add('expenses', {
      'category_id': 'cat_internet', 'vendor': 'MEO', 'description': 'Fibra 1 Gbps',
      'amount_cents': 4299, 'date': isoDate(monthsAgo(m, 3)), 'attachments': <String>[],
    });
  }
  add('expenses', {'category_id': 'cat_condo', 'vendor': 'Condomínio', 'description': 'Quota trimestral',
      'amount_cents': 18000, 'date': isoDate(monthsAgo(4, 5)), 'attachments': <String>[]});
  add('expenses', {'category_id': 'cat_repairs', 'vendor': 'Sr. Joaquim', 'description': 'Torneira da cozinha',
      'apartment_id': a1, 'amount_cents': 6500, 'date': isoDate(monthsAgo(3, 21)), 'attachments': <String>[]});
  add('expenses', {'category_id': 'cat_furniture', 'vendor': 'IKEA', 'description': 'Colchão e estante',
      'apartment_id': a2, 'room_id': rooms[4], 'amount_cents': 32900, 'date': isoDate(monthsAgo(2, 9)),
      'attachments': <String>[]});
  add('expenses', {'category_id': 'cat_cleaning', 'vendor': 'Continente', 'description': 'Detergentes',
      'amount_cents': 2340, 'date': isoDate(monthsAgo(1, 14)), 'attachments': <String>[]});
  final mistake = add('expenses', {'category_id': 'cat_material', 'vendor': 'Leroy Merlin',
      'description': 'Tinta branca 15L', 'amount_cents': 8999, 'date': isoDate(monthsAgo(0, 2)),
      'attachments': <String>[]});

  // Recurring bills (shown under "bills due soon").
  for (final (cat, vendor, cents, day) in [
    ('cat_energy', 'EDP Comercial', 8000, 12),
    ('cat_water', 'Águas do Porto', 5500, 18),
    ('cat_internet', 'MEO', 4299, 3),
  ]) {
    add('recurring_bills', {
      'category_id': cat, 'vendor': vendor, 'expected_cents': cents, 'frequency': 'monthly',
      'due_day': day, 'start_date': isoDate(monthsAgo(6, 1)), 'active': 1,
    });
  }

  await ledger.batch(changes);

  // Something for the checkpoint screen to show.
  await checkpoints.create('Demo: start', ledger.me);
  await ledger.delete('expenses', b, mistake);
  await ledger.upsert('tenants', b, {'phone': '912 999 000'}, id: tenants[0]);
}
