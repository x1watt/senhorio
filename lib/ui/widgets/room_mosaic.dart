// The rooms of a building at a glance: one tile per room, green when the
// rent is in order, red (pulsing) when overdue, grey when empty. Tiles
// grow in one after the other when the screen opens.

import 'package:flutter/material.dart';

import '../../data/zx_store.dart';
import '../../domain/rent_schedule.dart';
import 'common.dart';

enum RoomState { empty, ok, late }

class RoomTileData {
  final DbRow room;
  final DbRow? apartment;
  final RoomState state;
  final String? tenantName;
  final int owed;
  RoomTileData(this.room, this.apartment, this.state, this.tenantName, this.owed);

  static RoomState stateOf(LeaseStatus? status) {
    if (status == null) return RoomState.empty;
    return status.isLate ? RoomState.late : RoomState.ok;
  }
}

Color roomStateColor(RoomState s, ColorScheme scheme) => switch (s) {
      RoomState.empty => scheme.outline,
      RoomState.ok => const Color(0xFF2ECC71),
      RoomState.late => scheme.error,
    };

class RoomMosaic extends StatefulWidget {
  final List<RoomTileData> rooms;
  final void Function(DbRow room)? onTap;
  const RoomMosaic({super.key, required this.rooms, this.onTap});

  @override
  State<RoomMosaic> createState() => _RoomMosaicState();
}

class _RoomMosaicState extends State<RoomMosaic> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final rooms = widget.rooms;
    final late = rooms.where((r) => r.state == RoomState.late).length;
    final ok = rooms.where((r) => r.state == RoomState.ok).length;
    final empty = rooms.length - late - ok;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < rooms.length; i++)
            TweenAnimationBuilder<double>(
              key: ValueKey(rooms[i].room['id']),
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 350 + i * 90),
              curve: Curves.easeOutBack,
              builder: (context, t, child) => Transform.scale(scale: t, child: Opacity(opacity: t.clamp(0, 1), child: child)),
              child: _tile(context, rooms[i], scheme),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _legend(scheme.error, l.roomsLate(late)),
          const SizedBox(width: 12),
          _legend(const Color(0xFF2ECC71), l.roomsOk(ok)),
          const SizedBox(width: 12),
          _legend(scheme.outline, l.roomsEmpty(empty)),
        ]),
      ]),
    );
  }

  Widget _legend(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ]);

  Widget _tile(BuildContext context, RoomTileData r, ColorScheme scheme) {
    final color = roomStateColor(r.state, scheme);
    final tile = Container(
      width: 96,
      height: 76,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          Icon(switch (r.state) {
            RoomState.empty => Icons.bed_outlined,
            RoomState.ok => Icons.check_circle,
            RoomState.late => Icons.warning_amber_rounded,
          }, size: 16, color: color),
          const SizedBox(width: 4),
          Expanded(child: Text(r.room['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        ]),
        const SizedBox(height: 2),
        Text(
          r.state == RoomState.late
              ? context.money(r.owed)
              : (r.tenantName ?? (r.room['available'] == 0 ? context.l.keptEmpty : context.l.vacant)),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: r.state == RoomState.late ? color : null),
        ),
        if (r.apartment != null)
          Text(r.apartment!['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: scheme.outline)),
      ]),
    );
    final animated = r.state == RoomState.late
        ? AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25 + 0.45 * _pulse.value), blurRadius: 6 + 10 * _pulse.value)],
              ),
              child: child,
            ),
            child: tile,
          )
        : tile;
    return InkWell(borderRadius: BorderRadius.circular(12), onTap: widget.onTap == null ? null : () => widget.onTap!(r.room), child: animated);
  }
}
