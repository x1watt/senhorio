// A form described by a list of fields, used for every simple entity
// (building, apartment, room, tenant, lease, payment, bill, member...).

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import 'common.dart';

enum FieldType { text, multiline, money, integer, decimal, date, datetime, choice, toggle }

class FieldSpec {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final Map<String, String> options; // choice: value -> label
  final String? hint;
  const FieldSpec(this.key, this.label,
      {this.type = FieldType.text, this.required = false, this.options = const {}, this.hint});
}

/// Opens the form as a full-screen page; returns the values or null.
Future<Map<String, Object?>?> showEntityForm(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  Map<String, Object?> initial = const {},
}) =>
    Navigator.of(context).push<Map<String, Object?>>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EntityForm(title: title, fields: fields, initial: initial),
    ));

class EntityForm extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final Map<String, Object?> initial;
  const EntityForm({super.key, required this.title, required this.fields, this.initial = const {}});

  @override
  State<EntityForm> createState() => _EntityFormState();
}

class _EntityFormState extends State<EntityForm> {
  final _form = GlobalKey<FormState>();
  final _text = <String, TextEditingController>{};
  final _values = <String, Object?>{};

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final v = widget.initial[f.key];
      switch (f.type) {
        case FieldType.text:
        case FieldType.multiline:
        case FieldType.integer:
        case FieldType.decimal:
          _text[f.key] = TextEditingController(text: v?.toString() ?? '');
        case FieldType.money:
          _text[f.key] = TextEditingController(text: centsToInput(v as int?));
        case FieldType.date:
        case FieldType.datetime:
        case FieldType.choice:
          _values[f.key] = v;
        case FieldType.toggle:
          _values[f.key] = v == 1 || v == true;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final out = <String, Object?>{};
    for (final f in widget.fields) {
      final t = _text[f.key]?.text.trim();
      switch (f.type) {
        case FieldType.text:
        case FieldType.multiline:
          out[f.key] = t!.isEmpty ? null : t;
        case FieldType.money:
          out[f.key] = parseMoney(t!);
        case FieldType.integer:
          out[f.key] = int.tryParse(t!);
        case FieldType.decimal:
          out[f.key] = double.tryParse(t!.replaceAll(',', '.'));
        case FieldType.date:
        case FieldType.datetime:
        case FieldType.choice:
          out[f.key] = _values[f.key];
        case FieldType.toggle:
          out[f.key] = _values[f.key] == true ? 1 : 0;
      }
    }
    Navigator.pop(context, out);
  }

  String? _validate(FieldSpec f, String? v) {
    final s = v?.trim() ?? '';
    if (f.required && s.isEmpty) return context.l.required;
    if (s.isEmpty) return null;
    switch (f.type) {
      case FieldType.money:
        return parseMoney(s) == null ? context.l.invalidNumber : null;
      case FieldType.integer:
        return int.tryParse(s) == null ? context.l.invalidNumber : null;
      case FieldType.decimal:
        return double.tryParse(s.replaceAll(',', '.')) == null ? context.l.invalidNumber : null;
      default:
        return null;
    }
  }

  Widget _field(FieldSpec f) {
    switch (f.type) {
      case FieldType.text:
      case FieldType.multiline:
      case FieldType.money:
      case FieldType.integer:
      case FieldType.decimal:
        final numeric = f.type != FieldType.text && f.type != FieldType.multiline;
        return TextFormField(
          controller: _text[f.key],
          decoration: InputDecoration(labelText: f.label, hintText: f.hint,
              suffixText: f.type == FieldType.money ? '€' : null),
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true, signed: false)
              : (f.type == FieldType.multiline ? TextInputType.multiline : TextInputType.text),
          maxLines: f.type == FieldType.multiline ? 4 : 1,
          minLines: 1,
          validator: (v) => _validate(f, v),
        );
      case FieldType.date:
        final d = parseIsoDate(_values[f.key]);
        return FormField<String>(
          initialValue: _values[f.key] as String?,
          validator: (_) => f.required && _values[f.key] == null ? context.l.required : null,
          builder: (state) => InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: d ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _values[f.key] = isoDate(picked));
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: f.label, errorText: state.errorText,
                  suffixIcon: const Icon(Icons.calendar_today, size: 18)),
              child: Text(d == null ? '' : isoDate(d)),
            ),
          ),
        );
      case FieldType.datetime:
        final d = DateTime.tryParse(_values[f.key] as String? ?? '');
        return FormField<String>(
          initialValue: _values[f.key] as String?,
          validator: (_) => f.required && _values[f.key] == null ? context.l.required : null,
          builder: (state) => InkWell(
            onTap: () async {
              final day = await showDatePicker(
                context: context,
                initialDate: d ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (day == null || !mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(d ?? DateTime.now()),
              );
              if (time == null) return;
              setState(() => _values[f.key] =
                  isoDateTime(DateTime(day.year, day.month, day.day, time.hour, time.minute)));
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: f.label, errorText: state.errorText,
                  suffixIcon: const Icon(Icons.schedule, size: 18)),
              child: Text(d == null ? '' : formatDateTime(context, d)),
            ),
          ),
        );
      case FieldType.choice:
        return DropdownButtonFormField<String>(
          initialValue: f.options.containsKey(_values[f.key]) ? _values[f.key] as String? : null,
          decoration: InputDecoration(labelText: f.label),
          isExpanded: true,
          items: [
            for (final o in f.options.entries)
              DropdownMenuItem(value: o.key, child: Text(o.value, overflow: TextOverflow.ellipsis)),
          ],
          validator: (v) => f.required && v == null ? context.l.required : null,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldType.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _values[f.key] == true,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(onPressed: _save, child: Text(context.l.save)),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final f in widget.fields)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: _field(f)),
            ],
          ),
        ),
      );
}
