import 'package:bsat/services/phone_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:sim_data/sim_data.dart';

import '../../services/sqlite_service.dart';
import '../../utils/numbers.dart';

class AirtimePerDay extends StatefulWidget {
  const AirtimePerDay({super.key});

  @override
  State<AirtimePerDay> createState() => _AirtimePerDayState();
}

class _AirtimePerDayState extends State<AirtimePerDay> {
  SQLiteService sqLiteService = SQLiteService();

  final List<Map<String, dynamic>> offerVolumes = [];

  int defaultSimSubId = -1;
  List<SimCard> simCards = [];
  List<int> balances = [];

  int airtimeDay = 0;
  int airtimeYesterday = 0;
  int airtimeWeek = 0;
  int airtimeMonth = 0;

  bool _showAirtimeBalances = false;

  String _selectedTimeframe = 'week';

  Future<List<Map<String, dynamic>>> getTotalAmountPerDate(int days) async {
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
      (i) => getNormalDate(
        now.subtract(Duration(days: days - 1 - i)),
      ),
    );

    final result = await sqLiteService.rawQueryInput('''
      SELECT date, SUM(amount) as total
      FROM transactions
      WHERE timeStamp >= ?
        AND (status LIKE '${TransactionStatuses.done}%' 
          OR status = '${TransactionStatuses.advancedUssd}'
          OR status = '${TransactionStatuses.doneConfirmed}')
      GROUP BY date
      ORDER BY timeStamp ASC
    ''', [startTimestamp]);

    airtimeDay = result.firstWhere(
      (row) => row['date'] == getNormalDate(now),
      orElse: () => {'total': 0},
    )['total'] as int;

    airtimeYesterday = result.firstWhere(
      (row) =>
          row['date'] == getNormalDate(now.subtract(const Duration(days: 1))),
      orElse: () => {'total': 0},
    )['total'] as int;

    airtimeWeek = result.fold(0, (sum, row) {
      List<String> parts = (row['date'] as String).split('/');
      DateTime date = DateTime(
        int.parse(parts[2]), // year
        int.parse(parts[1]), // month
        int.parse(parts[0]), // day
      );
      if (date.isAfter(now.subtract(const Duration(days: 6)))) {
        return sum + (row['total'] as int? ?? 0);
      }
      return sum;
    });

    airtimeMonth = result.fold(0, (sum, row) {
      List<String> parts = (row['date'] as String).split('/');
      DateTime date = DateTime(
        int.parse(parts[2]), // year
        int.parse(parts[1]), // month
        int.parse(parts[0]), // day
      );
      if (date.isAfter(now.subtract(const Duration(days: 29)))) {
        return sum + (row['total'] as int? ?? 0);
      }
      return sum;
    });

    final Map<String, num> dateToTotal = {
      for (var row in result) row['date'] as String: row['total'] ?? 0
    };

    List<Map<String, dynamic>> res = dateList
        .map((date) => {
              'date': date,
              'total': dateToTotal[date] ?? 0,
            })
        .toList();

    return res;
  }

  Widget bottomTitles(double value, TitleMeta meta) {
    const style = TextStyle(fontSize: 12);
    int idx = value.toInt();
    String text = '';

    // Decide label interval based on timeframe
    int labelInterval = _selectedTimeframe == 'week'
        ? 1
        : _selectedTimeframe == 'month'
            ? 4
            : 50;

    // Only show label at the interval
    if (idx % labelInterval != 0) return const SizedBox.shrink();

    if (idx < offerVolumes.length) {
      if (_selectedTimeframe == 'week') {
        text = getDayOfWeek(
          toDateTime(offerVolumes[idx]['date'], "00:00:00", delim: '/'),
        );
        if (text.length > 5) text = text.substring(0, 3);
      } else {
        final dateParts = offerVolumes[idx]['date'].split('/');
        text = "${dateParts[0]}/${dateParts[1]}";
      }
    }

    return SideTitleWidget(
      meta: meta,
      child: Text(text, style: style),
    );
  }

  Widget topTitles(double value, TitleMeta meta) {
    const style = TextStyle(fontSize: 10);
    int idx = value.toInt();

    // Use the same interval logic as bottomTitles
    int labelInterval = _selectedTimeframe == 'week'
        ? 1
        : _selectedTimeframe == 'month'
            ? 4
            : 50;

    if (idx % labelInterval != 0) return const SizedBox.shrink();

    String text = idx < offerVolumes.length
        ? Numbers.formatNumber((offerVolumes[idx]['total'] as num).toInt(),
            leastK: 1000)
        : '';
    return SideTitleWidget(
      meta: meta,
      child: Text(text, style: style),
    );
  }

  Widget leftTitles(double value, TitleMeta meta) {
    if (value == meta.max) return Container();
    const style = TextStyle(
        // fontSize: 10,
        );
    return SideTitleWidget(
      meta: meta,
      child: Text(
        Numbers.formatNumber(value.toInt(), leastK: 1000),
        style: style,
      ),
    );
  }

  void _getBalances() async {
    debugPrint("Getting balances");
    if (!mounted) return;

    if(_showAirtimeBalances) {
      setState(() {
        balances.clear();
      });
    } else {
      return;
    }

    for (var i in simCards) {
      debugPrint(
          "Getting balance for ${i.displayName} (${i.slotIndex}), id = ${i.subscriptionId}");
      int balance = await PhoneService()
          .getAirtimeBalance(subscriptionId: i.subscriptionId);

      if (!mounted) return;
      debugPrint("Balance: $balance");

      setState(() {
        balances.add(balance);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDataForTimeframe();
    SimDataPlugin.getSimData().then((value) async {
      defaultSimSubId = (await PhoneService().getAllDialSims()).first;
      setState(() {
        simCards = value.cards;
      });

      _getBalances();
    });
  }

  Future<void> _loadDataForTimeframe() async {
    int days = _selectedTimeframe == 'week'
        ? 7
        : _selectedTimeframe == 'month'
            ? 30
            : 365;
    final data = await getTotalAmountPerDate(days);
    setState(() {
      offerVolumes.clear();
      offerVolumes.addAll(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Balances'),
            IconButton(
              icon: Icon(
                _showAirtimeBalances ? Icons.visibility_off : Icons.visibility,
                size: 15,
              ),
              onPressed: () {
                setState(() {
                  _showAirtimeBalances = !_showAirtimeBalances;
                  if (_showAirtimeBalances) {
                    _getBalances();
                  } else {
                    balances.clear();
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: kPagePadding / 2),
        Row(
          spacing: kPagePadding / 2,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var entry in simCards.asMap().entries)
              Expanded(
                child: Container(
                  // padding: const EdgeInsets.symmetric(vertical: 4.0),
                  padding: const EdgeInsets.all(kPagePadding / 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(kBorderRadius),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '''${entry.value.displayName} ${Numbers.formatNumber(entry.value.slotIndex + 1)} ${entry.value.subscriptionId == defaultSimSubId ? '(Default)' : ''} ''',
                        style: TextStyle(
                            // fontSize: 16,
                            // color: Theme.of(context).textTheme.bodyText1?.color,
                            ),
                      ),
                      const SizedBox(height: kPagePadding / 4),
                      Text(
                        (entry.key < balances.length)
                            ? "Ksh${balances[entry.key]}"
                            : '...',
                        style: TextStyle(
                          // fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).indicatorColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: kPagePadding),
        const Text("Usage"),
        const SizedBox(height: kPagePadding / 2),
        Container(
          padding: const EdgeInsets.symmetric(vertical: kPagePadding),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(kBorderRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      const Text('Today'),
                      const SizedBox(height: kPagePadding / 3),
                      Text(
                        Numbers.formatNumber(airtimeDay),
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
                        Numbers.formatNumber(airtimeYesterday),
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
                        Numbers.formatNumber(airtimeWeek),
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
                        Numbers.formatNumber(airtimeMonth),
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
            ],
          ),
        ),
        const SizedBox(height: kPagePadding * 2),
        Padding(
          padding: const EdgeInsets.only(bottom: kPagePadding),
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
              await _loadDataForTimeframe();
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
          aspectRatio: 1.66,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.center,
                barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        String date = offerVolumes[group.x.toInt()]['date'];
                        String total =
                            offerVolumes[group.x.toInt()]['total'].toString();
                        return BarTooltipItem(
                          '$date\n',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          children: [
                            TextSpan(
                              text: total,
                              style: const TextStyle(
                                color: Colors.yellow,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        );
                      },
                    )),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _selectedTimeframe == 'week'
                          ? 1
                          : _selectedTimeframe == 'month'
                              ? 10 // show every 4th label for month
                              : 7, // show every 7th label for year
                      getTitlesWidget: bottomTitles,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: leftTitles,
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _selectedTimeframe == 'week'
                          ? 1
                          : _selectedTimeframe == 'month'
                              ? 4 // show every 4th label for month
                              : 7, // show every 7th label for year
                      getTitlesWidget: topTitles,
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: false),
                groupsSpace: 12,
                barGroups: List.generate(offerVolumes.length, (idx) {
                  return BarChartGroupData(
                    x: idx,
                    barRods: [
                      BarChartRodData(
                        toY: offerVolumes[idx]['total'].toDouble(),
                        color: kPrimaryColor,
                        width: 16,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                    // showingTooltipIndicators: [0],
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
