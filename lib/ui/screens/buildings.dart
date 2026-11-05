import 'package:flutter/material.dart';

import '../../data/zx_store.dart';
import '../../domain/rent_schedule.dart';
import '../forms.dart';
import '../widgets/common.dart';
import '../widgets/entity_form.dart';
import '../widgets/room_mosaic.dart';
import 'building_tabs.dart';
import 'room.dart';

class BuildingsScreen extends StatelessWidget {
  const BuildingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.buildings)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_home_work),
        label: Text(l.newBuilding),
        onPressed: () async {
          final v = await showEntityForm(context,
              title: l.newBuilding, fields: buildingFields(l), initial: {'currency': 'EUR'});
          if (v != null && context.mounted) {
            await guarded(context, () => context.app.ledger.createBuilding(v));
          }
        },
      ),
      body: LiveFuture<List<DbRow>>(
        load: (a) => a.q.buildings(),
        builder: (context, rows) => rows.isEmpty
            ? EmptyState(Icons.apartment, l.noBuildings)
            : ListView(children: [
                for (final b in rows)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.apartment)),
                    title: Text(b['name'] as String? ?? ''),
                    subtitle: b['address'] == null ? null : Text(b['address'] as String),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => BuildingScreen(buildingId: b['id'] as String))),
                  ),
              ]),
      ),
    );
  }
}

class BuildingScreen extends StatelessWidget {
  final String buildingId;
  const BuildingScreen({super.key, required this.buildingId});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return LiveFuture<DbRow?>(
      load: (a) => a.q.byId('buildings', buildingId),
      builder: (context, b) {
        if (b == null || b['deleted'] == 1) {
          return Scaffold(appBar: AppBar(), body: EmptyState(Icons.delete, l.deleted));
        }
        final isOwner = b['owner'] == context.app.identity.pubkey;
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text(b['name'] as String? ?? ''),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: l.edit,
                  onPressed: () => editEntity(context,
                      table: 'buildings', building: buildingId, title: l.edit,
                      fields: buildingFields(l), row: b),
                ),
                if (isOwner)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l.delete,
                    onPressed: () async {
                      if (await confirm(context, l.confirmDelete) && context.mounted) {
                        await guarded(context, () => context.app.ledger.delete('buildings', buildingId, buildingId));
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                  ),
              ],
              bottom: TabBar(isScrollable: true, tabs: [
                Tab(text: l.units),
                Tab(text: l.tenants),
                Tab(text: l.recurringBills),
                Tab(text: l.members),
              ]),
            ),
            body: TabBarView(children: [
              UnitsTab(building: b),
              TenantsTab(building: b),
              RecurringBillsTab(building: b),
              MembersTab(building: b),
            ]),
          ),
        );
      },
    );
  }
}

/// Apartments with their rooms, each room showing who rents it and whether
/// the rent is late.
class UnitsTab extends StatelessWidget {
  final DbRow building;
  const UnitsTab({super.key, required this.building});

  String get bid => building['id'] as String;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return LiveFuture<_UnitsData>(
      load: (a) async {
        final apts = await a.q.apartments(bid);
        final rooms = await a.q.rooms(bid);
        final leases = await a.q.leases(building: bid);
        final tenants = {for (final t in await a.q.tenants(bid)) t['id']: t};
        final pays = await a.q.payments(building: bid);
        final now = DateTime.now();
        final active = <String, LeaseStatus>{};
        for (final le in leases) {
          final end = le['end_date'] as String?;
          if (end != null && end.compareTo(todayIso()) < 0) continue;
          active[le['room_id'] as String] = leaseStatus(
              le, pays.where((p) => p['lease_id'] == le['id']).toList(), now);
        }
        return _UnitsData(apts, rooms, active, tenants);
      },
      builder: (context, d) => Scaffold(
        floatingActionButton: FloatingActionButton(
          heroTag: 'unit-$bid',
          tooltip: l.newApartment,
          onPressed: () => _addMenu(context, d),
          child: const Icon(Icons.add),
        ),
        body: d.apartments.isEmpty
            ? EmptyState(Icons.door_front_door, l.noApartments)
            : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                if (d.rooms.isNotEmpty)
                  RoomMosaic(
                    rooms: [
                      for (final r in d.rooms)
                        RoomTileData(
                          r,
                          d.apartments.where((a) => a['id'] == r['apartment_id']).firstOrNull,
                          RoomTileData.stateOf(d.active[r['id']]),
                          d.tenants[d.active[r['id']]?.lease['tenant_id']]?['name'] as String?,
                          d.active[r['id']]?.owedLate ?? 0,
                        ),
                    ],
                    onTap: (r) => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => RoomScreen(roomId: r['id'] as String))),
                  ),
                for (final apt in d.apartments)
                  _apartmentTile(context, apt, d),
              ]),
      ),
    );
  }

  Widget _apartmentTile(BuildContext context, DbRow apt, _UnitsData d) {
    final l = context.l;
    final rooms = d.rooms.where((r) => r['apartment_id'] == apt['id']).toList();
    final rented = rooms.where((r) => d.active.containsKey(r['id'])).length;
    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(Icons.door_front_door),
      title: Text(apt['name'] as String? ?? ''),
      subtitle: Text(l.roomsRented(rented, rooms.length)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') {
            await editEntity(context, table: 'apartments', building: bid, title: l.edit,
                fields: apartmentFields(l), row: apt);
          } else if (v == 'room') {
            await editEntity(context, table: 'rooms', building: bid, title: l.newRoom,
                fields: roomFields(l, d.apartments),
                defaults: {'apartment_id': apt['id'], 'available': 1});
          } else if (v == 'delete' && await confirm(context, l.confirmDelete) && context.mounted) {
            await guarded(context, () => context.app.ledger.delete('apartments', bid, apt['id'] as String));
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'room', child: Text(l.newRoom)),
          PopupMenuItem(value: 'edit', child: Text(l.edit)),
          PopupMenuItem(value: 'delete', child: Text(l.delete)),
        ],
      ),
      children: [
        for (final r in rooms) _roomTile(context, r, d),
        if (rooms.isEmpty) ListTile(dense: true, title: Text(l.noRooms)),
      ],
    );
  }

  Widget _roomTile(BuildContext context, DbRow r, _UnitsData d) {
    final l = context.l;
    final st = d.active[r['id']];
    final tenant = st == null ? null : d.tenants[st.lease['tenant_id']];
    final Widget badge;
    if (st == null) {
      badge = Chip(
        label: Text(r['available'] == 0 ? l.keptEmpty : l.vacant),
        visualDensity: VisualDensity.compact,
      );
    } else if (st.isLate) {
      badge = Chip(
        avatar: const Icon(Icons.warning_amber, size: 16, color: Colors.white),
        label: Text(context.money(st.owedLate), style: const TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).colorScheme.error,
        visualDensity: VisualDensity.compact,
      );
    } else {
      badge = Chip(
        avatar: const Icon(Icons.check, size: 16),
        label: Text(l.upToDate),
        visualDensity: VisualDensity.compact,
      );
    }
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 56, right: 16),
      leading: const Icon(Icons.bed_outlined),
      title: Text(r['name'] as String? ?? ''),
      subtitle: tenant == null ? null : Text(tenant['name'] as String? ?? ''),
      trailing: badge,
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => RoomScreen(roomId: r['id'] as String))),
    );
  }

  Future<void> _addMenu(BuildContext context, _UnitsData d) async {
    final l = context.l;
    if (d.apartments.isEmpty) {
      await editEntity(context, table: 'apartments', building: bid, title: l.newApartment,
          fields: apartmentFields(l));
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.door_front_door), title: Text(l.newApartment),
              onTap: () => Navigator.pop(c, 'apt')),
          ListTile(leading: const Icon(Icons.bed_outlined), title: Text(l.newRoom),
              onTap: () => Navigator.pop(c, 'room')),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'apt') {
      await editEntity(context, table: 'apartments', building: bid, title: l.newApartment,
          fields: apartmentFields(l));
    } else if (choice == 'room') {
      await editEntity(context, table: 'rooms', building: bid, title: l.newRoom,
          fields: roomFields(l, d.apartments), defaults: {'available': 1});
    }
  }
}

class _UnitsData {
  final List<DbRow> apartments, rooms;
  final Map<String, LeaseStatus> active; // room id -> current lease status
  final Map<Object?, DbRow> tenants;
  _UnitsData(this.apartments, this.rooms, this.active, this.tenants);
}

