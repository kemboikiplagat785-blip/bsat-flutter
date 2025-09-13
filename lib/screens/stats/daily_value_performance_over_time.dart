import 'package:bsat/utils/constants.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../services/sqlite_service.dart';
import '../../utils/date_ops.dart';

class ValuePerformanceOverTime extends StatefulWidget {
  const ValuePerformanceOverTime({super.key});

  @override
  State<ValuePerformanceOverTime> createState() =>
      _ValuePerformanceOverTimeState();
}

class _ValuePerformanceOverTimeState extends State<ValuePerformanceOverTime> {
  // List<Map<String, dynamic>> salesPerDay = [];
  bool isShowingMainData = true;
  int days = 7;

  String _selectedTimeframe = 'week';

  final List<Map<String, dynamic>> offerVolumes = [];

  List<Map<String, dynamic>> salesData = [];

  Map<int, double> salesWeekAmount = {};

  Future<void> loadSalesData() async {
    salesData = await getSalesPerDay(days);
    setState(() {});
  }

  void seperateAmounts() {
    for (var sale in salesData) {
      if (salesWeekAmount.containsKey(sale['amount'])) {
        salesWeekAmount[sale['amount']] =
            (salesWeekAmount[sale['amount']] ?? 0) + 1;
      } else {
        salesWeekAmount[sale['amount']] = 1;
      }
    }
  }

  Future<List<Map<String, dynamic>>> getSalesPerDay(int days) async {
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = getNormalDate(startDate);
    final startTimestamp =
        DateTime(startDate.year, startDate.month, startDate.day)
            .millisecondsSinceEpoch;
    final endTimestamp = DateTime(now.year, now.month, now.day, 23, 59, 59)
        .millisecondsSinceEpoch;

    List<String> dateList = List.generate(
      days,
      (i) => getNormalDate(now.subtract(Duration(days: days - 1 - i))),
    );

    final result = await SQLiteService().rawQueryInput('''
      SELECT date, amount, COUNT(amount) as total
      FROM transactions
      WHERE timeStamp >= ?
        AND (status LIKE '%${TransactionStatuses.done}%' 
            OR status LIKE '%${TransactionStatuses.doneConfirmed}%'
            OR status LIKE '%${TransactionStatuses.advancedUssd}%')
      GROUP BY date, amount
      ORDER BY timeStamp ASC
    ''', [startTimestamp]);

    // 1. Collect all unique amounts
    final Set<int> allAmounts = {};
    final Map<String, Map<int, int>> dateToAmounts = {};
    for (var row in result) {
      final date = row['date'] as String;
      final amount = row['amount'] is int
          ? row['amount']
          : int.tryParse(row['amount'].toString()) ?? 0;
      final total = row['total'] is int
          ? row['total']
          : int.tryParse(row['total'].toString()) ?? 0;
      allAmounts.add(amount);
      dateToAmounts.putIfAbsent(date, () => {});
      dateToAmounts[date]![amount] = total;
    }

    // 2. For each date, fill missing amounts with 0
    return dateList.map((date) {
      final amounts = <int, int>{};
      for (final amount in allAmounts) {
        amounts[amount] = dateToAmounts[date]?[amount] ?? 0;
      }
      return {
        'date': date,
        'amounts': amounts,
      };
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    loadSalesData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: DropdownButtonFormField<String>(
            value: _selectedTimeframe,
            items: const [
              DropdownMenuItem(value: 'week', child: Text('Week')),
              DropdownMenuItem(value: 'month', child: Text('Month')),
              DropdownMenuItem(value: 'year', child: Text('Year')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() {
                _selectedTimeframe = value;
                days = value == 'week'
                    ? 7
                    : value == 'month'
                        ? 30
                        : 365;
              });
              await loadSalesData();
            },
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kBorderRadius),
              ),
              labelText: 'Timeframe',
            ),
          ),
        ),
        AspectRatio(
          aspectRatio: 1.23,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 37),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                      right: kPagePadding, left: kPagePadding),
                  child: _LineChart(
                    isShowingMainData: isShowingMainData,
                    salesData: salesData,
                    selectedTimeframe: _selectedTimeframe,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineChart extends StatelessWidget {
  final bool isShowingMainData;
  final List<Map<String, dynamic>> salesData;
  final selectedTimeframe;

  const _LineChart({
    required this.isShowingMainData,
    required this.salesData,
    required this.selectedTimeframe,
  });

  @override
  Widget build(BuildContext context) {
    return LineChart(
      mainData(),
      duration: const Duration(milliseconds: 250),
    );
  }

  LineChartData mainData() {
    // Get all unique amounts (sorted for legend consistency)
    final allAmounts = <int>{
      for (final day in salesData) ...((day['amounts'] as Map<int, int>).keys)
    }.toList()
      ..sort();

    // debugPrint('All amounts: $allAmounts');
    // debugPrint('Sales per day: $salesData');

    // Build a line for each amount
    final lines = <LineChartBarData>[];
    for (var i = 0; i < allAmounts.length; i++) {
      final amount = allAmounts[i];
      // debugPrint('Amount: $amount');
      final color = kSectionColors[i % kSectionColors.length];
      final spots = List<FlSpot>.generate(
        salesData.length,
        (j) => FlSpot(
          j.toDouble(),
          ((salesData[j]['amounts'] as Map<int, int>)[amount] ?? 0).toDouble(),
        ),
      );
      if (spots.every((spot) => spot.y == 0)) {
        // Skip lines with all zero values
        continue;
      }
      lines.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    // Find maxY for scaling, set a minimum (e.g. 10)
    final maxY = (lines
                .expand((line) => line.spots)
                .map((spot) => spot.y)
                .fold<double>(0, (prev, y) => y > prev ? y : prev) *
            1.2)
        .clamp(10.0, double.infinity);

    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (List<LineBarSpot> touchedSpots) {
            return touchedSpots.map((spot) {
              final amount = allAmounts[spot.barIndex];
              return LineTooltipItem(
                'Ksh',
                TextStyle(
                  color: kSectionColors[spot.barIndex % kSectionColors.length],
                  fontWeight: FontWeight.w100,
                  fontSize: 11,
                ),
                children: [
                  TextSpan(
                    text: ' $amount  (${salesData[spot.x.toInt()]['date']})\n',
                    style: const TextStyle(
                        color: Colors.yellow, fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: '${spot.y.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.yellow, fontWeight: FontWeight.bold),
                  ),
                ],
              );
            }).toList();
          },
        ),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              // total count for total number of spots
              String text = '';
              if (salesData.length > idx) {
                final amounts = salesData[idx]['amounts'] as Map<int, int>;
                final total = amounts.values.fold<int>(0, (sum, v) => sum + v);
                text = total.toString();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            // interval: 7,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              String text = '';
              if (salesData.length > idx) {
                if (selectedTimeframe == 'week') {
                  // Show day of week (short)
                  text = getDayOfWeek(toDateTime(
                    salesData[idx]['date'],
                    "00:00:00",
                    delim: '/',
                  )).substring(0, 3);
                } else {
                  // Show actual date (e.g. 12/06 or 12/06/25)
                  final dateParts = salesData[idx]['date'].split('/');
                  // if (selectedTimeframe == 'month') {
                  // Show dd/MM
                  text = "${dateParts[0]}/${dateParts[1]}";
                  // } else {
                  //   // Show dd/MM/yy
                  //   text = "${dateParts[0]}/${dateParts[1]}/${dateParts[2].substring(2)}";
                  // }
                }
              }

              return SideTitleWidget(
                meta: meta,
                child: Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (maxY / 5).clamp(1, double.infinity),
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  value == 0 ? '' : "${value.toInt()}\t\t",
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.left,
                ),
              );
            },
            reservedSize: 42,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: false,
        border: Border.all(color: Colors.indigo, width: 4),
      ),
      minX: 0,
      maxX: (salesData.isNotEmpty ? salesData.length - 1 : 6).toDouble(),
      minY: 0,
      maxY: maxY,
      lineBarsData: lines,
    );
  }
}
