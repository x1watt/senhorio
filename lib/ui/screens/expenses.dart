import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/zx_store.dart';
import '../../domain/category_learner.dart';
import '../forms.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String? _building;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.expenses)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.newExpense),
        onPressed: () => openExpenseForm(context, prefill: {'building_id': ?_building}),
      ),
      body: LiveFuture<(List<DbRow>, List<DbRow>, List<DbRow>)>(
        load: (a) async => (await a.q.buildings(), await a.q.categories(),
            await a.q.expenses(building: _building)),
        builder: (context, d) {
          final (buildings, cats, rows) = d;
          final catById = {for (final c in cats) c['id']: c};
          final bName = {for (final b in buildings) b['id']: b['name']};
          final byMonth = <String, List<DbRow>>{};
          for (final e in rows) {
            byMonth.putIfAbsent((e['date'] as String? ?? '').padRight(7).substring(0, 7), () => []).add(e);
          }
          return Column(children: [
            if (buildings.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(children: [
                  ChoiceChip(label: Text(l.all), selected: _building == null,
                      onSelected: (_) => setState(() => _building = null)),
                  for (final b in buildings)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(label: Text(b['name'] as String? ?? ''),
                          selected: _building == b['id'],
                          onSelected: (_) => setState(() => _building = b['id'] as String)),
                    ),
                ]),
              ),
            Expanded(
              child: rows.isEmpty
                  ? EmptyState(Icons.receipt_long, l.noExpenses)
                  : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                      for (final m in byMonth.entries) ...[
                        SectionHeader(m.key,
                            trailing: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(context.money(m.value.fold<int>(0, (a, e) => a + ((e['amount_cents'] as int?) ?? 0)))),
                            )),
                        for (final e in m.value)
                          ListTile(
                            leading: CategoryAvatar(catById[e['category_id']]),
                            title: Text((e['vendor'] as String?) ?? categoryName(context, catById[e['category_id']])),
                            subtitle: Text([
                              e['date'],
                              if (_building == null) bName[e['building_id']],
                              e['description'],
                            ].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_attachments(e).isNotEmpty) const Icon(Icons.attach_file, size: 16),
                              Text(context.money(e['amount_cents'] as int?)),
                            ]),
                            onTap: () => openExpenseForm(context, expense: e),
                          ),
                      ],
                    ]),
            ),
          ]);
        },
      ),
    );
  }
}

List<String> _attachments(DbRow e) {
  final s = e['attachments'] as String?;
  if (s == null || s.isEmpty) return [];
  return (jsonDecode(s) as List).cast<String>();
}

Future<void> openExpenseForm(BuildContext context, {DbRow? expense, Map<String, Object?> prefill = const {}}) =>
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ExpenseForm(expense: expense, prefill: prefill),
    ));

class ExpenseForm extends StatefulWidget {
  final DbRow? expense;
  final Map<String, Object?> prefill;
  const ExpenseForm({super.key, this.expense, this.prefill = const {}});
  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, Object?> _v;
  final _amount = TextEditingController();
  final _vendor = TextEditingController();
  final _desc = TextEditingController();
  final _qty = TextEditingController();
  List<String> _files = [];
  List<DbRow> _buildings = [], _apartments = [], _rooms = [], _cats = [];
  List<Suggestion> _suggestions = [];
  List<String> _vendors = [];
  Timer? _debounce;
  bool _saving = false;
  bool _userPickedCategory = false;

  @override
  void initState() {
    super.initState();
    _v = {...?widget.expense, ...widget.prefill};
    _v['date'] ??= todayIso();
    _amount.text = centsToInput(_v['amount_cents'] as int?);
    _vendor.text = (_v['vendor'] as String?) ?? '';
    _desc.text = (_v['description'] as String?) ?? '';
    _qty.text = _v['quantity']?.toString() ?? '';
    _files = _attachments(_v);
    _userPickedCategory = _v['category_id'] != null;
    for (final c in [_amount, _vendor, _desc]) {
      c.addListener(_scheduleSuggest);
    }
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_amount, _vendor, _desc, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  AppState get app => context.app;

  Future<void> _load() async {
    _buildings = await app.q.buildings();
    _cats = await app.q.categories();
    _vendors = (await app.store.query(
            'SELECT vendor, count(*) n FROM expenses WHERE deleted = 0 AND vendor IS NOT NULL GROUP BY vendor ORDER BY n DESC LIMIT 200'))
        .map((r) => r['vendor'] as String)
        .toList();
    if (_v['building_id'] == null && _buildings.length == 1) _v['building_id'] = _buildings.first['id'];
    await _loadUnits();
    await _suggest();
  }

  Future<void> _loadUnits() async {
    final b = _v['building_id'] as String?;
    _apartments = b == null ? [] : await app.q.apartments(b);
    _rooms = b == null ? [] : await app.q.rooms(b, apartment: _v['apartment_id'] as String?);
    if (mounted) setState(() {});
  }

  void _scheduleSuggest() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _suggest);
  }

  Future<void> _suggest() async {
    final learner = await app.learner();
    final s = learner.suggest(ExpenseFeatures(
      vendor: _vendor.text,
      description: _desc.text,
      amountCents: parseMoney(_amount.text) ?? 0,
      building: _v['building_id'] as String?,
      apartment: _v['apartment_id'] as String?,
    ));
    if (!mounted) return;
    setState(() {
      _suggestions = s;
      if (!_userPickedCategory && s.isNotEmpty && s.first.score > 0.6) {
        _v['category_id'] = s.first.categoryId;
      }
    });
  }

  DbRow? get _category => _cats.where((c) => c['id'] == _v['category_id']).firstOrNull;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final fields = <String, Object?>{
      'amount_cents': parseMoney(_amount.text),
      'date': _v['date'],
      'vendor': _vendor.text.trim().isEmpty ? null : _vendor.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'category_id': _v['category_id'],
      'apartment_id': _v['apartment_id'],
      'room_id': _v['room_id'],
      'quantity': double.tryParse(_qty.text.replaceAll(',', '.')),
      'unit': _category?['unit'],
      'recurring_bill_id': _v['recurring_bill_id'],
      'paid_by': _v['paid_by'] ?? app.identity.pubkey,
      'attachments': _files,
    };
    final old = widget.expense;
    final changed = old == null
        ? fields
        : {
            for (final e in fields.entries)
              if ((e.value is List ? jsonEncode(e.value) : e.value) != old[e.key]) e.key: e.value
          };
    await guarded(context, () async {
      if (changed.isNotEmpty) {
        await app.ledger.upsert('expenses', _v['building_id'] as String, changed,
            id: old?['id'] as String?);
      }
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final suggested = _suggestions.map((s) => s.categoryId).toSet();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expense == null ? l.newExpense : l.expense),
        actions: [
          if (widget.expense != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, l.confirmDelete) && context.mounted) {
                  await guarded(context, () => app.ledger.delete('expenses',
                      widget.expense!['building_id'] as String, widget.expense!['id'] as String));
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          TextButton(onPressed: _saving ? null : _save, child: Text(l.save)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _amount,
            autofocus: widget.expense == null,
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: InputDecoration(labelText: l.amount, suffixText: '€'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => parseMoney(v ?? '') == null ? l.invalidNumber : null,
          ),
          const SizedBox(height: 12),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _vendor.text),
            optionsBuilder: (t) => t.text.isEmpty
                ? const []
                : _vendors.where((v) => normalize(v).contains(normalize(t.text))),
            onSelected: (v) => _vendor.text = v,
            fieldViewBuilder: (context, ctrl, focus, _) {
              ctrl.addListener(() {
                if (_vendor.text != ctrl.text) _vendor.text = ctrl.text;
              });
              return TextFormField(
                controller: ctrl,
                focusNode: focus,
                decoration: InputDecoration(labelText: l.vendor),
              );
            },
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _desc, decoration: InputDecoration(labelText: l.description)),
          const SizedBox(height: 16),
          Text(l.category, style: Theme.of(context).textTheme.labelLarge),
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Icon(Icons.auto_awesome, size: 16),
                const SizedBox(width: 4),
                Text(l.suggested, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in [
              ..._suggestions.map((s) => _cats.where((c) => c['id'] == s.categoryId).firstOrNull).whereType<DbRow>(),
              ..._cats.where((c) => !suggested.contains(c['id'])),
            ])
              ChoiceChip(
                avatar: Icon(categoryIcons[c['icon']] ?? Icons.category, size: 16,
                    color: Color((c['color'] as int?) ?? 0xFF9E9E9E)),
                label: Text(categoryName(context, c)),
                selected: _v['category_id'] == c['id'],
                side: suggested.contains(c['id'])
                    ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
                    : null,
                onSelected: (_) => setState(() {
                  _v['category_id'] = c['id'];
                  _userPickedCategory = true;
                }),
              ),
          ]),
          if (_category?['unit'] != null) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _qty,
              decoration: InputDecoration(labelText: l.consumption, suffixText: _category!['unit'] as String),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context,
                  initialDate: parseIsoDate(_v['date']) ?? DateTime.now(),
                  firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (d != null) setState(() => _v['date'] = isoDate(d));
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: l.date, suffixIcon: const Icon(Icons.calendar_today, size: 18)),
              child: Text(_v['date'] as String? ?? ''),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _buildings.any((b) => b['id'] == _v['building_id']) ? _v['building_id'] as String? : null,
            decoration: InputDecoration(labelText: l.building),
            isExpanded: true,
            validator: (v) => v == null ? l.required : null,
            items: [for (final b in _buildings) DropdownMenuItem(value: b['id'] as String, child: Text(b['name'] as String? ?? ''))],
            onChanged: (v) {
              _v['building_id'] = v;
              _v['apartment_id'] = null;
              _v['room_id'] = null;
              _loadUnits();
              _scheduleSuggest();
            },
          ),
          const SizedBox(height: 12),
          if (_apartments.isNotEmpty)
            DropdownButtonFormField<String?>(
              key: ValueKey('apt-${_v['building_id']}'),
              initialValue: _apartments.any((a) => a['id'] == _v['apartment_id']) ? _v['apartment_id'] as String? : null,
              decoration: InputDecoration(labelText: l.apartmentOptional),
              isExpanded: true,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(l.wholeBuilding)),
                for (final a in _apartments) DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String? ?? '')),
              ],
              onChanged: (v) {
                _v['apartment_id'] = v;
                _v['room_id'] = null;
                _loadUnits();
                _scheduleSuggest();
              },
            ),
          if (_v['apartment_id'] != null && _rooms.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('room-${_v['apartment_id']}'),
              initialValue: _rooms.any((r) => r['id'] == _v['room_id']) ? _v['room_id'] as String? : null,
              decoration: InputDecoration(labelText: l.roomOptional),
              isExpanded: true,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(l.wholeApartment)),
                for (final r in _rooms) DropdownMenuItem(value: r['id'] as String, child: Text(r['name'] as String? ?? '')),
              ],
              onChanged: (v) => _v['room_id'] = v,
            ),
          ],
          const SizedBox(height: 16),
          Text(l.receipts, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          AttachmentList(shas: _files, onChanged: (f) => setState(() => _files = f)),
        ]),
      ),
    );
  }
}
