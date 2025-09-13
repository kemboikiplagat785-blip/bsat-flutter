import 'package:bsat/utils/constants.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../services/sqlite_service.dart';
import 'package:bsat/utils/date_ops.dart';

import '../../utils/numbers.dart';

class CommissionGraph extends StatefulWidget {
  const CommissionGraph({super.key});

  @override
  State<CommissionGraph> createState() => _CommissionGraphState();
}

class _CommissionGraphState extends State<CommissionGraph> {
  List<Color> gradientColors = [
    kIndigoColor,
    kPrimaryColor,
  ];

  bool showAvg = false;
  List<Map<String, dynamic>> commissionPerDay = [];
  // int days = 7; // or any number of days you want to show
  double highestCommission = 0;
  double avgCommission = 0;
  double commissionToday = 0;
  double commissionYesterday = 0;
  double commissionWeek = 0;
  double commissionMonth = 0;

  String _selectedTimeframe = 'week';

  int get days {
    switch (_selectedTimeframe) {
      case 'month':
        return 30;
      case 'year':
        return 365;
      case 'week':
      default:
        return 7;
    }
  }

  @override
  void initState() {
    super.initState();
    loadCommissionData();
  }

  Future<void> loadCommissionData() async {
    final data = await getCommissionPerDay(days);
    setState(() {
      commissionPerDay = data;
    });

    // debugPrint("COmmission $data");
  }

  Future<List<Map<String, dynamic>>> getCommissionPerDay(int days) async {
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = getNormalDate(startDate);
    final startTimestamp =
        DateTime(startDate.year, startDate.month, startDate.day)
            .millisecondsSinceEpoch;
    final endTimestamp = DateTime(now.year, now.month, now.day, 23, 59, 59)
        .millisecondsSinceEpoch;

    // Prepare the list of allowed amounts for SQL IN clause
    final allowedAmounts =
        kInitialCodes.map((e) => e['amount'] as int).toList();
    final placeholders = List.filled(allowedAmounts.length, '?').join(',');

    final result = await SQLiteService().rawQueryInput('''
      SELECT date, SUM(amount * 0.1) as total
      FROM transactions
      WHERE timeStamp >= ?
        AND amount IN ($placeholders)
          AND (status LIKE '%${TransactionStatuses.done}%'
          OR status LIKE '%${TransactionStatuses.doneConfirmed}%')
      GROUP BY date
      ORDER BY timeStamp ASC
    ''', [startTimestamp, ...allowedAmounts]);

    highestCommission = result.isNotEmpty
        ? ((result
            .map((e) => (e['total'] as num?) ?? 0)
            .reduce((a, b) => a > b ? a : b)).toDouble())
        : 0.0;

    avgCommission = result.isNotEmpty
        ? (result
                .map((e) => (e['total'] as num?) ?? 0)
                .reduce((a, b) => a + b) /
            result.length)
        : 0.0;

    commissionToday = ((result.firstWhere(
      (row) => row['date'] == getNormalDate(now),
      orElse: () => {'total': 0},
    )['total']) as num)
        .toDouble();
    commissionYesterday = (result.firstWhere(
      (row) =>
          row['date'] == getNormalDate(now.subtract(const Duration(days: 1))),
      orElse: () => {'total': 0},
    )['total'] as num)
        .toDouble();
    commissionWeek = result.fold(0.0, (sum, row) {
      List<String> parts = (row['date'] as String).split('/');
      DateTime date = DateTime(
        int.parse(parts[2]), // year
        int.parse(parts[1]), // month
        int.parse(parts[0]), // day
      );
      if (date.isAfter(now.subtract(const Duration(days: 6)))) {
        return sum + ((row['total'] as num?) ?? 0);
      }
      return sum;
    });
    commissionMonth = result.fold(0.0, (sum, row) {
      List<String> parts = (row['date'] as String).split('/');
      DateTime date = DateTime(
        int.parse(parts[2]), // year
        int.parse(parts[1]), // month
        int.parse(parts[0]), // day
      );
      if (date.isAfter(now.subtract(const Duration(days: 29)))) {
        return sum + ((row['total'] as num?) ?? 0);
      }
      return sum;
    });

    // debugPrint('startDateStr: $startDateStr');
    // debugPrint('allowedAmounts: $allowedAmounts');
    // debugPrint('Query result: $result');

    // Map result to a map for quick lookup
    final Map<String, num> dateToTotal = {
      for (var row in result) row['date'] as String: row['total'] ?? 0
    };

    // Build the final list, filling missing dates with 0
    List<String> dateList = List.generate(
      days,
      (i) => getNormalDate(now.subtract(Duration(days: days - 1 - i))),
    );

    return dateList
        .map((date) => {
              'date': date,
              'total': dateToTotal[date] ?? 0,
            })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(vertical: kPagePadding),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(kBorderRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  const Text('Today'),
                  const SizedBox(height: kPagePadding / 3),
                  Text(
                    Numbers.formatNumber(commissionToday.toInt()),
                    style: TextStyle(
                      // fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).indicatorColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: kPagePadding),
              Column(
                children: [
                  const Text('Yesterday'),
                  const SizedBox(height: kPagePadding / 3),
                  Text(
                    Numbers.formatNumber(commissionYesterday.toInt()),
                    style: TextStyle(
                      // fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).indicatorColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: kPagePadding),
              Column(
                children: [
                  const Text('Week'),
                  const SizedBox(height: kPagePadding / 3),
                  Text(
                    Numbers.formatNumber(commissionWeek.toInt()),
                    style: const TextStyle(
                      // fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kErrorColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: kPagePadding),
              Column(
                children: [
                  const Text('Month'),
                  const SizedBox(height: kPagePadding / 3),
                  Text(
                    Numbers.formatNumber(commissionMonth.toInt()),
                    style: const TextStyle(
                      // fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kDarkerGreen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: kPagePadding / 2),
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
              });
              await loadCommissionData();
            },
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kBorderRadius),
              ),
              labelText: 'Timeframe',
            ),
          ),
        ),
        const SizedBox(height: kPagePadding * 2),
        AspectRatio(
          aspectRatio: 1.70,
          child: Padding(
            padding: const EdgeInsets.only(
              right: 18,
              left: 12,
              top: 24,
              bottom: 12,
            ),
            child: LineChart(
              mainData(),
            ),
          ),
        ),
      ],
    );
  }

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
    );
    Widget text;
    // Show date labels from commissionPerDay
    if (commissionPerDay.isNotEmpty &&
        value.toInt() < commissionPerDay.length) {
      if (_selectedTimeframe == 'month' || _selectedTimeframe == 'year') {
        // Show dd/MM
        text = Text(
          (commissionPerDay[value.toInt()]['date'] as String?)
                  ?.substring(0, 5) ??
              '',
          style: style,
        );
      } else {
        text = Text(
          // (commissionPerDay[value.toInt()]['date'] as String?)?.substring(0, 2) ??
          getDayOfWeek(
            toDateTime(
              commissionPerDay[value.toInt()]['date'],
              "00:00:00",
              delim: '/',
            ),
          ).substring(0, 3),
          // '',
          style: style,
        );
      }
    } else {
      text = const Text('', style: style);
    }

    return SideTitleWidget(
      meta: meta,
      child: text,
    );
  }

  Widget topTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      // fontSize: 16,
    );
    Widget text;
    // Show date labels from commissionPerDay
    if (commissionPerDay.isNotEmpty &&
        value.toInt() < commissionPerDay.length) {
      text = Text(
        Numbers.formatNumber(
                (commissionPerDay[value.toInt()]['total'] as num).toInt(),
                leastK: 1000) ??
            '',
        style: style,
      );
    } else {
      text = const Text('', style: style);
    }

    return SideTitleWidget(
      meta: meta,
      child: text,
    );
  }

  Widget leftTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
        // fontWeight: FontWeight.bold,
        // fontSize: 15,
        );
    String text =
        value == 0 ? '' : Numbers.formatNumber(value.toInt(), leastK: 1000);
    return Text(text, style: style, textAlign: TextAlign.left);
  }

  LineChartData mainData() {
    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (List<LineBarSpot> touchedSpots) {
            return touchedSpots.map((spot) {
              return LineTooltipItem(
                '${commissionPerDay[spot.x.toInt()]['date']}:\n',
                const TextStyle(
                  color: kLightColor,
                  fontWeight: FontWeight.w100,
                ),
                children: [
                  TextSpan(
                    text: '${(spot.y as num?)?.toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(
                        color: Colors.yellow, fontWeight: FontWeight.bold),
                  ),
                ],
              );
            }).toList();
          },
        ),
      ),
      extraLinesData: ExtraLinesData(
        // showHorizontalLines: true,
        horizontalLines: [
          HorizontalLine(
            y: highestCommission > 0 ? highestCommission : 1,
            color: Colors.red.withOpacity(0.5),
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
          HorizontalLine(
            y: avgCommission > 0 ? avgCommission : 1,
            color: Colors.green.withOpacity(0.5),
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
        ],
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
            // interval: 1,
            getTitlesWidget: topTitleWidgets,
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            // interval: 1,
            getTitlesWidget: bottomTitleWidgets,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: highestCommission > 0 ? highestCommission / 5 : 1,
            getTitlesWidget: leftTitleWidgets,
            reservedSize: 42,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: false,
      ),
      minX: 0,
      maxX: (commissionPerDay.isNotEmpty ? commissionPerDay.length - 1 : 6)
          .toDouble(),
      minY: 0,
      maxY: commissionPerDay.isNotEmpty
          ? (commissionPerDay
                  .map((e) => (e['total'] as num?) ?? 0)
                  .reduce((a, b) => a > b ? a : b) *
              1.2)
          : 6,
      lineBarsData: [
        LineChartBarData(
          spots: commissionPerDay.isNotEmpty
              ? List.generate(
                  commissionPerDay.length,
                  (i) => FlSpot(
                    i.toDouble(),
                    (commissionPerDay[i]['total'] as num?)?.toDouble() ?? 0,
                  ),
                )
              : const [
                  FlSpot(0, 0),
                ],
          isCurved: true,
          gradient: LinearGradient(
            colors: gradientColors,
          ),
          barWidth: 5,
          isStrokeCapRound: true,
          dotData: const FlDotData(
            show: false,
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: gradientColors
                  .map((color) => color.withOpacity(0.3))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}
