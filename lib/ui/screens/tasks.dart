// Work given to workers (cleaning the stairs, an apartment...): a time
// range, photo evidence from the worker, and an approval by the staff.
// Workers only hold the tasks given to them (sync/sync_engine.dart).

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/queries.dart';
import '../../data/zx_store.dart';
import '../../domain/roles.dart';
import '../forms.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart';
import '../widgets/entity_form.dart';
import '../widgets/people.dart';

List<String> taskPhotos(DbRow t) {
  final s = t['photos'] as String?;
  if (s == null || s.isEmpty) return const [];
  return (jsonDecode(s) as List).cast<String>();
}

Color taskColor(BuildContext context, String? status) => switch (status) {
      'done' => Colors.orange,
      'approved' => const Color(0xFF2ECC71),
      'rejected' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.outline,
    };

IconData taskIcon(String? status) => switch (status) {
      'done' => Icons.hourglass_top,
      'approved' => Icons.verified,
      'rejected' => Icons.cancel,
      _ => Icons.radio_button_unchecked,
    };

class TaskStatusChip extends StatelessWidget {
  final String? status;
  const TaskStatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = taskColor(context, status);
    return Chip(
      avatar: Icon(taskIcon(status), size: 16, color: c),
      label: Text(context.l.taskStatus(status ?? 'open'), style: TextStyle(color: c)),
      side: BorderSide(color: c),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// The workers of [building] (by member row), for the assignee choice.
Future<Map<String, String>> workerOptions(BuildContext context, String building) async {
  final app = context.app;
  final members = await app.q.members(building);
  final people = await app.q.people();
  if (!context.mounted) return {};
  return {
    for (final m in members)
      if (roleOf(m['role']) == Role.worker) m['pubkey'] as String: personName(context, m['pubkey'] as String, people),
  };
}

/// The form of a task; saves it. Returns the id, or null when cancelled.
Future<String?> editTask(BuildContext context, String building, {DbRow? row, Map<String, Object?> defaults = const {}}) async {
  final l = context.l;
  final app = context.app;
  final workers = await workerOptions(context, building);
  if (!context.mounted) return null;
  if (workers.isEmpty) {
    context.toast(l.noWorkersYet);
    return null;
  }
  final apts = await app.q.apartments(building);
  final rooms = await app.q.rooms(building);
  if (!context.mounted) return null;
  final aptName = {for (final a in apts) a['id']: a['name'] as String? ?? ''};
  final fields = [
    FieldSpec('title', l.title, required: true),
    FieldSpec('assignee', l.assignee, type: FieldType.choice, options: workers, required: true),
    FieldSpec('starts_at', l.startsAt, type: FieldType.datetime, required: true),
    FieldSpec('ends_at', l.endsAt, type: FieldType.datetime),
    FieldSpec('apartment_id', l.apartmentOptional, type: FieldType.choice,
        options: {'': l.wholeBuilding, ...optionsOf(apts, (r) => r['name'] as String? ?? '')}),
    FieldSpec('room_id', l.roomOptional, type: FieldType.choice,
        options: {'': '—', ...optionsOf(rooms, (r) => '${aptName[r['apartment_id']] ?? ''} · ${r['name'] ?? ''}')}),
    FieldSpec('place', l.place, hint: l.placeHint),
    FieldSpec('instructions', l.instructions, type: FieldType.multiline),
  ];
  final values = await showEntityForm(context, title: row == null ? l.newTask : l.edit,
      fields: fields, initial: row ?? defaults);
  if (values == null || !context.mounted) return null;
  // The worker never receives the rooms: name the place in words.
  if ((values['place'] as String?)?.isEmpty ?? true) {
    final room = rooms.where((r) => r['id'] == values['room_id']).firstOrNull;
    values['place'] = room != null
        ? '${aptName[room['apartment_id']] ?? ''} · ${room['name'] ?? ''}'
        : (aptName[values['apartment_id']] ?? l.wholeBuilding);
  }
  for (final k in ['apartment_id', 'room_id']) {
    if (values[k] == '') values[k] = null;
  }
  String? id;
  await guarded(context, () async {
    final changed = row == null
        ? {'status': 'open', ...defaults, ...values}
        : {for (final e in values.entries) if (row[e.key] != e.value) e.key: e.value};
    if (changed.isEmpty) return;
    id = await app.ledger.upsert('tasks', building, changed, id: row?['id'] as String?);
  });
  return id;
}

class TasksTab extends StatelessWidget {
  final DbRow building;
  final Role? role; // mine
  const TasksTab({super.key, required this.building, required this.role});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final bid = building['id'] as String;
    final me = context.app.identity.pubkey;
    final staff = role?.canReviewTasks ?? false;
    return LiveFuture<(List<DbRow>, Map<String, Person>)>(
      load: (a) async => (await a.q.tasks(building: bid, assignee: staff ? null : me), await a.q.people()),
      builder: (context, d) {
        final (tasks, people) = d;
        final review = tasks.where((t) => t['status'] == 'done').toList();
        final open = tasks.where((t) => t['status'] == 'open' || t['status'] == 'rejected' || t['status'] == null).toList()
          ..sort((a, b) => (a['starts_at'] as String? ?? '').compareTo(b['starts_at'] as String? ?? ''));
        final closed = tasks.where((t) => t['status'] == 'approved').toList();
        return Scaffold(
          floatingActionButton: !staff
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'task-$bid',
                  icon: const Icon(Icons.add_task),
                  label: Text(l.newTask),
                  onPressed: () => editTask(context, bid, defaults: {
                    'starts_at': isoDateTime(DateTime.now().add(const Duration(days: 1))),
                  }),
                ),
          body: tasks.isEmpty
              ? EmptyState(Icons.cleaning_services, staff ? l.noTasksStaff : l.noTasksWorker)
              : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                  if (!staff)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l.workerView, style: Theme.of(context).textTheme.bodySmall),
                    ),
                  if (review.isNotEmpty) SectionHeader(l.toReview),
                  for (final t in review) _tile(context, t, people, staff),
                  if (open.isNotEmpty) SectionHeader(l.upcoming),
                  for (final t in open) _tile(context, t, people, staff),
                  if (closed.isNotEmpty) SectionHeader(l.taskStatus('approved')),
                  for (final t in closed) _tile(context, t, people, staff),
                ]),
        );
      },
    );
  }

  Widget _tile(BuildContext context, DbRow t, Map<String, Person> people, bool staff) {
    final from = DateTime.tryParse(t['starts_at'] as String? ?? ''), to = DateTime.tryParse(t['ends_at'] as String? ?? '');
    final who = t['assignee'] as String?;
    return ListTile(
      leading: Icon(taskIcon(t['status'] as String?), color: taskColor(context, t['status'] as String?)),
      title: Text(t['title'] as String? ?? ''),
      subtitle: Text([
        ?t['place'] as String?,
        formatTimeRange(context, from, to),
        if (staff && who != null) personName(context, who, people),
      ].where((s) => s.isNotEmpty).join(' · ')),
      trailing: TaskStatusChip(t['status'] as String?),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskScreen(taskId: t['id'] as String))),
    );
  }
}

class TaskScreen extends StatelessWidget {
  final String taskId;
  const TaskScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final me = context.app.identity.pubkey;
    return LiveFuture<(DbRow?, Role?, Map<String, Person>)>(
      load: (a) async {
        final t = await a.q.byId('tasks', taskId);
        return (t, t == null ? null : await a.ledger.myRole(t['building_id'] as String), await a.q.people());
      },
      builder: (context, d) {
        final (t, role, people) = d;
        if (t == null || t['deleted'] == 1) {
          return Scaffold(appBar: AppBar(), body: EmptyState(Icons.delete, l.deleted));
        }
        final bid = t['building_id'] as String;
        final status = t['status'] as String? ?? 'open';
        final staff = role?.canReviewTasks ?? false;
        final mine = t['assignee'] == me;
        final photos = taskPhotos(t);
        final canWork = mine && status != 'approved';
        final from = DateTime.tryParse(t['starts_at'] as String? ?? ''), to = DateTime.tryParse(t['ends_at'] as String? ?? '');
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(t['title'] as String? ?? ''),
            actions: [
              if (staff)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await editTask(context, bid, row: t);
                    } else if (v == 'week' || v == 'month') {
                      await _repeat(context, t, v == 'week' ? const Duration(days: 7) : null);
                    } else if (v == 'delete' && await confirm(context, l.confirmDelete) && context.mounted) {
                      await guarded(context, () => context.app.ledger.delete('tasks', bid, taskId));
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(l.edit)),
                    PopupMenuItem(value: 'week', child: Text(l.repeatNextWeek)),
                    PopupMenuItem(value: 'month', child: Text(l.repeatNextMonth)),
                    PopupMenuItem(value: 'delete', child: Text(l.delete)),
                  ],
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text(t['place'] as String? ?? '', style: Theme.of(context).textTheme.titleMedium)),
              TaskStatusChip(status),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.schedule, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(formatTimeRange(context, from, to))),
            ]),
            if (t['assignee'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  PersonAvatar(pubkey: t['assignee'] as String, people: people, radius: 14),
                  const SizedBox(width: 8),
                  Text(personName(context, t['assignee'] as String, people)),
                ]),
              ),
            if ((t['instructions'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              Text(l.instructions, style: Theme.of(context).textTheme.titleSmall),
              Text(t['instructions'] as String),
            ],
            const Divider(height: 32),
            Text(l.photoEvidence, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            if (canWork) Text(l.photoEvidenceHelp, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            AttachmentList(
              shas: photos,
              onChanged: !canWork
                  ? null
                  : (list) => guarded(context, () => context.app.ledger.upsert('tasks', bid, {'photos': list}, id: taskId)),
            ),
            if (t['done_at'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(l.doneAt(formatDateTime(context, DateTime.tryParse(t['done_at'] as String) ?? DateTime.now())),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if ((t['done_note'] as String?)?.isNotEmpty ?? false) Text(t['done_note'] as String),
            if (t['reviewed_by'] != null) ...[
              const SizedBox(height: 8),
              Text(l.reviewedBy(personName(context, t['reviewed_by'] as String, people)),
                  style: TextStyle(color: taskColor(context, status))),
              if ((t['review_note'] as String?)?.isNotEmpty ?? false) Text(t['review_note'] as String),
            ],
            const SizedBox(height: 24),
            if (canWork && status != 'done')
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text(l.markDone),
                onPressed: photos.isEmpty ? null : () => _markDone(context, bid),
              ),
            if (canWork && status != 'done' && photos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l.photoEvidenceRequired, textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
            if (staff && status == 'done')
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: Text(l.reject),
                    onPressed: () => _review(context, bid, 'rejected'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.verified),
                    label: Text(l.approve),
                    onPressed: () => _review(context, bid, 'approved'),
                  ),
                ),
              ]),
          ]),
        );
      },
    );
  }

  Future<void> _markDone(BuildContext context, String bid) async {
    final l = context.l;
    final note = await _askNote(context, l.markDone);
    if (note == null || !context.mounted) return;
    await guarded(context, () => context.app.ledger.upsert('tasks', bid, {
          'status': 'done',
          'done_at': isoDateTime(DateTime.now()),
          'done_note': note.isEmpty ? null : note,
        }, id: taskId));
  }

  Future<void> _review(BuildContext context, String bid, String status) async {
    final l = context.l;
    final note = await _askNote(context, status == 'approved' ? l.approve : l.reject);
    if (note == null || !context.mounted) return;
    await guarded(context, () => context.app.ledger.upsert('tasks', bid, {
          'status': status,
          'reviewed_by': context.app.identity.pubkey,
          'reviewed_at': isoDateTime(DateTime.now()),
          'review_note': note.isEmpty ? null : note,
        }, id: taskId));
  }

  /// An optional note; null when cancelled.
  Future<String?> _askNote(BuildContext context, String title) async {
    final l = context.l;
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 3, minLines: 1,
            decoration: InputDecoration(labelText: l.noteOptional)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(l.ok)),
        ],
      ),
    );
    ctrl.dispose();
    return v;
  }

  /// A copy of [t] one week (or one month, when [by] is null) later.
  Future<void> _repeat(BuildContext context, DbRow t, Duration? by) async {
    DateTime? shift(Object? s) {
      final d = DateTime.tryParse(s as String? ?? '');
      if (d == null) return null;
      return by != null ? d.add(by) : DateTime(d.year, d.month + 1, d.day, d.hour, d.minute);
    }
    final starts = shift(t['starts_at']), ends = shift(t['ends_at']);
    await editTask(context, t['building_id'] as String, defaults: {
      for (final k in ['title', 'place', 'apartment_id', 'room_id', 'assignee', 'instructions']) k: t[k],
      'starts_at': starts == null ? null : isoDateTime(starts),
      'ends_at': ends == null ? null : isoDateTime(ends),
    });
  }
}
