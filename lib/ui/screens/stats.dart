import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/zx_store.dart';
import '../../domain/stats.dart';
import '../widgets/common.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _Data {
  final List<DbRow> buildings, cats, rooms, leases, payments, expenses;
  _Data(this.buildings, this.cats, this.rooms, this.leases, this.payments, this.expenses);
}

class _StatsScreenState extends State<StatsScreen> {
  String? _building;
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.statistics),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _year--)),
          Center(child: Text('$_year')),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _year++)),
        ],
      ),
      body: LiveFuture<_Data>(
        load: (a) async {
          final b = _building;
          final rooms = b == null ? await a.q.allRooms() : await a.q.rooms(b);
          return _Data(await a.q.buildings(), await a.q.categories(), rooms,
              await a.q.leases(building: b), await a.q.payments(building: b), await a.q.expenses(building: b));
        },
        builder: (context, d) => _body(context, d),
      ),
    );
  }

  Widget _body(BuildContext context, _Data d) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final until = _year == now.year ? now : DateTime(_year, 12, 31);
    final months = monthKeys(until, 12);
    final totals = monthlyTotals(d.payments, d.expenses, months);
    final catTotals = byCategory(d.expenses, '$_year');
    final catById = {for (final c in d.cats) c['id']: c};
    final occ = occupancy(d.rooms, d.leases, now);
    final coll = collection(d.leases, d.payments, _year, now);
    final yearIncome = d.payments.where((p) => (p['paid_on'] as String? ?? '').startsWith('$_year'))
        .fold<int>(0, (s, p) => s + ((p['amount_cents'] as int?) ?? 0));
    final yearExp = catTotals.values.fold<int>(0, (a, b) => a + b);
    final utilities = d.cats.where((c) => c['unit'] != null || c['key'] == 'internet').toList();

    return ListView(padding: const EdgeInsets.all(12), children: [
      if (d.buildings.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ChoiceChip(label: Text(l.all), selected: _building == null,
                onSelected: (_) => setState(() => _building = null)),
            for (final b in d.buildings)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(label: Text(b['name'] as String? ?? ''), selected: _building == b['id'],
                    onSelected: (_) => setState(() => _building = b['id'] as String)),
              ),
          ]),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _kpi(context, l.income, context.money(yearIncome)),
        _kpi(context, l.expenses, context.money(yearExp)),
        _kpi(context, l.net, context.money(yearIncome - yearExp)),
        _kpi(context, l.occupancy, '${(occ.rate * 100).round()}% (${occ.rented}/${occ.rooms})'),
        _kpi(context, l.rentCollected,
            coll.expected == 0 ? '-' : '${(coll.paid * 100 / coll.expected).round()}%'),
      ]),
      _card(context, l.incomeVsExpenses, SizedBox(
        height: 220,
        child: BarChart(BarChartData(
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44,
                getTitlesWidget: (v, m) => Text(_short(v), style: const TextStyle(fontSize: 10)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
                getTitlesWidget: (v, m) => Text(months[v.toInt()].substring(5), style: const TextStyle(fontSize: 10)))),
          ),
          barGroups: [
            for (var i = 0; i < totals.length; i++)
              BarChartGroupData(x: i, barsSpace: 2, barRods: [
                BarChartRodData(toY: totals[i].income / 100, color: Colors.green, width: 6),
                BarChartRodData(toY: totals[i].expenses / 100, color: scheme.error, width: 6),
              ]),
          ],
        )),
      )),
      if (catTotals.isNotEmpty)
        _card(context, l.expensesByCategory, Column(children: [
          SizedBox(
            height: 200,
            child: PieChart(PieChartData(
              sectionsSpace: 1,
              centerSpaceRadius: 40,
              sections: [
                for (final e in catTotals.entries)
                  PieChartSectionData(
                    value: e.value / 100,
                    color: Color((catById[e.key]?['color'] as int?) ?? 0xFF9E9E9E),
                    title: yearExp == 0 ? '' : '${(e.value * 100 / yearExp).round()}%',
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
              ],
            )),
          ),
          for (final e in (catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
            ListTile(
              dense: true,
              leading: CategoryAvatar(catById[e.key], radius: 14),
              title: Text(categoryName(context, catById[e.key])),
              trailing: Text(context.money(e.value)),
            ),
        ])),
      for (final c in utilities) _utilityCard(context, d, c, months),
    ]);
  }

  Widget _utilityCard(BuildContext context, _Data d, DbRow cat, List<String> months) {
    final l = context.l;
    final series = utilitySeries(d.expenses, cat['id'] as String, months);
    if (series.every((p) => p.cents == 0)) return const SizedBox.shrink();
    final color = Color((cat['color'] as int?) ?? 0xFF9E9E9E);
    final unit = cat['unit'] as String?;
    final totalQ = series.fold<double>(0, (a, p) => a + p.quantity);
    final totalC = series.fold<int>(0, (a, p) => a + p.cents);
    final rented = occupancy(d.rooms, d.leases, DateTime.now()).rented;
    return _card(context, categoryName(context, cat), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 160,
        child: LineChart(LineChartData(
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44,
                getTitlesWidget: (v, m) => Text(_short(v), style: const TextStyle(fontSize: 10)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 2,
                getTitlesWidget: (v, m) => Text(months[v.toInt()].substring(5), style: const TextStyle(fontSize: 10)))),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), series[i].cents / 100)],
              color: color,
              barWidth: 3,
              isCurved: true,
              preventCurveOverShooting: true,
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
            ),
          ],
        )),
      ),
      const SizedBox(height: 8),
      Text('${l.last12Months}: ${context.money(totalC)}'
          '${totalQ > 0 && unit != null ? ' · ${totalQ.toStringAsFixed(1)} $unit · ${context.money((totalC / totalQ).round())}/$unit' : ''}'
          '${rented > 0 ? ' · ${context.money(totalC ~/ 12 ~/ rented)} ${l.perRoomMonth}' : ''}'),
    ]));
  }

  static String _short(double v) =>
      v.abs() >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);

  Widget _kpi(BuildContext context, String label, String value) => SizedBox(
        width: 160,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ]),
          ),
        ),
      );

  Widget _card(BuildContext context, String title, Widget child) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}
