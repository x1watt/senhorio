// Field lists of every simple entity, and the generic "edit and save" flow.

import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../data/zx_store.dart';
import '../domain/recurrence.dart';
import '../l10n/gen/app_localizations.dart';
import 'widgets/common.dart';
import 'widgets/entity_form.dart';

Map<String, String> frequencyOptions(AppLocalizations l) =>
    {for (final f in Frequency.values) f.name: l.frequency(f.name)};

Map<String, String> optionsOf(List<DbRow> rows, String Function(DbRow) label) =>
    {for (final r in rows) r['id'] as String: label(r)};

List<FieldSpec> buildingFields(AppLocalizations l) => [
      FieldSpec('name', l.name, required: true),
      FieldSpec('address', l.address, type: FieldType.multiline),
      FieldSpec('currency', l.currency, hint: 'EUR'),
      FieldSpec('notes', l.notes, type: FieldType.multiline),
    ];

List<FieldSpec> apartmentFields(AppLocalizations l) => [
      FieldSpec('name', l.name, required: true),
      FieldSpec('floor', l.floor),
      FieldSpec('notes', l.notes, type: FieldType.multiline),
    ];

List<FieldSpec> roomFields(AppLocalizations l, List<DbRow> apartments) => [
      FieldSpec('name', l.name, required: true),
      FieldSpec('apartment_id', l.apartment,
          type: FieldType.choice, options: optionsOf(apartments, (r) => r['name'] as String? ?? ''),
          required: true),
      FieldSpec('area_m2', l.area, type: FieldType.decimal),
      FieldSpec('available', l.availableForRent, type: FieldType.toggle),
      FieldSpec('notes', l.notes, type: FieldType.multiline),
    ];

List<FieldSpec> tenantFields(AppLocalizations l) => [
      FieldSpec('name', l.name, required: true),
      FieldSpec('phone', l.phone),
      FieldSpec('email', l.email),
      FieldSpec('tax_id', l.taxId),
      FieldSpec('notes', l.notes, type: FieldType.multiline),
    ];

List<FieldSpec> leaseFields(AppLocalizations l, List<DbRow> tenants) => [
      FieldSpec('tenant_id', l.tenant,
          type: FieldType.choice, options: optionsOf(tenants, (r) => r['name'] as String? ?? ''),
          required: true),
      FieldSpec('rent_cents', l.rent, type: FieldType.money, required: true),
      FieldSpec('frequency', l.frequencyLabel, type: FieldType.choice, options: frequencyOptions(l), required: true),
      FieldSpec('due_day', l.dueDay, type: FieldType.integer, required: true, hint: l.dueDayHint),
      FieldSpec('start_date', l.startDate, type: FieldType.date, required: true),
      FieldSpec('end_date', l.endDate, type: FieldType.date),
      FieldSpec('grace_days', l.graceDays, type: FieldType.integer),
      FieldSpec('deposit_cents', l.deposit, type: FieldType.money),
      FieldSpec('notes', l.notes, type: FieldType.multiline),
    ];

List<FieldSpec> paymentFields(AppLocalizations l, Map<String, String> periods) => [
      FieldSpec('period', l.period, type: FieldType.choice, options: periods, required: true),
      FieldSpec('amount_cents', l.amount, type: FieldType.money, required: true),
      FieldSpec('paid_on', l.paidOn, type: FieldType.date, required: true),
      FieldSpec('method', l.method, hint: l.methodHint),
      FieldSpec('notes', l.notes, type: FieldType.multiline),
    ];

List<FieldSpec> recurringBillFields(BuildContext context, List<DbRow> categories, List<DbRow> apartments) {
  final l = context.l;
  return [
    FieldSpec('vendor', l.vendor, required: true),
    FieldSpec('category_id', l.category,
        type: FieldType.choice, options: optionsOf(categories, (r) => categoryName(context, r)), required: true),
    FieldSpec('apartment_id', l.apartmentOptional,
        type: FieldType.choice, options: {'': l.wholeBuilding, ...optionsOf(apartments, (r) => r['name'] as String? ?? '')}),
    FieldSpec('expected_cents', l.expectedAmount, type: FieldType.money),
    FieldSpec('frequency', l.frequencyLabel, type: FieldType.choice, options: frequencyOptions(l), required: true),
    FieldSpec('due_day', l.dueDay, type: FieldType.integer, required: true),
    FieldSpec('start_date', l.startDate, type: FieldType.date, required: true),
    FieldSpec('active', l.active, type: FieldType.toggle),
    FieldSpec('description', l.description, type: FieldType.multiline),
  ];
}

List<FieldSpec> categoryFields(AppLocalizations l) => [
      FieldSpec('name', l.name, required: true),
      FieldSpec('icon', l.icon, type: FieldType.choice,
          options: {for (final k in categoryIcons.keys) k: k}),
      FieldSpec('unit', l.consumptionUnit, hint: 'kWh, m³, GB'),
    ];

/// Shows the form for [table] and saves it as a signed change.
/// Returns the id, or null when cancelled.
Future<String?> editEntity(
  BuildContext context, {
  required String table,
  required String building,
  required String title,
  required List<FieldSpec> fields,
  DbRow? row,
  Map<String, Object?> defaults = const {},
}) async {
  final values = await showEntityForm(context,
      title: title, fields: fields, initial: row ?? defaults);
  if (values == null || !context.mounted) return null;
  final app = context.app;
  String? id;
  await guarded(context, () async {
    // Only send what changed (smaller events, fewer LWW conflicts).
    final changed = row == null
        ? {...defaults, ...values}
        : {for (final e in values.entries) if (row[e.key] != e.value) e.key: e.value};
    if (changed.isEmpty) {
      id = row?['id'] as String?;
      return;
    }
    id = await app.ledger.upsert(table, building, changed, id: row?['id'] as String?);
  });
  return id;
}

String todayIso() => isoDate(DateTime.now());
