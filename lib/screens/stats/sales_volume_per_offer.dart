import 'package:bsat/utils/constants.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/sqlite_service.dart';
import '../../utils/date_ops.dart';
import '../../utils/numbers.dart';
import '../transactions/transaction_history.dart';

class SalesVolumePerOffer extends StatefulWidget {
  const SalesVolumePerOffer({super.key});

  @override
  State<StatefulWidget> createState() => SalesVolumePerOfferState();
}

class SalesVolumePerOfferState extends State<SalesVolumePerOffer> {
  int touchedIndex = -1;

  String _selectedTimeframe = 'week';

  // Example data: each map contains 'label' and 'value'
  final List<Map<String, dynamic>> offerVolumes = [];
  final SQLiteService _sqliteService = SQLiteService();

  List salesDay = [];
  List salesYesterday = [];
  List salesWeek = [];
  List salesMonth = [];

  Map<int, List<FlSpot>> amountSpots = {};

  Map<int, double> salesDayAmount = {};
  Map<int, double> salesYesterdayAmount = {};
  Map<int, double> salesWeekAmount = {};
  Map<int, double> salesMonthAmount = {};

  double commissionToday = 0;
  double commissionYesterday = 0;
  double commissionWeek = 0;
  double commissionMonth = 0;

  int comission = 0;

  void getSales() async {
    String dateToday = getNormalDate(DateTime.now());
    String dateYesterday =
        getNormalDate(DateTime.now().subtract(const Duration(days: 1)));

    salesDay = await _sqliteService
        .queryCustom('transactions', 'date = ?', [dateToday]);

    salesYesterday = await _sqliteService
        .queryCustom('transactions', 'date = ?', [dateYesterday]);

    salesWeek = await _sqliteService.queryCustom(
        'transactions', 'timeStamp >= ?', [
      DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch
    ]);

    salesMonth = await _sqliteService.queryCustom(
        'transactions', 'timeStamp >= ?', [
      DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch
    ]);

    seperateAmounts();

    setState(() {});
  }

  void seperateAmounts() {
    for (var sale in salesDay) {
      if (salesDayAmount.containsKey(sale['amount'])) {
        salesDayAmount[sale['amount']] =
            (salesDayAmount[sale['amount']] ?? 0) + 1;
      } else {
        salesDayAmount[sale['amount']] = 1;
      }
      if (kInitialCodes.any((e) => e['amount'] == sale['amount'])) {
        // debugPrint('Sale amount: ${sale['amount']}');
        // comission += ((sale['amount'] as int) * 0.1) as int;

        commissionToday += (sale['amount'] * 0.1);
      }
    }

    for (var sale in salesYesterday) {
      if (salesYesterdayAmount.containsKey(sale['amount'])) {
        salesYesterdayAmount[sale['amount']] =
            (salesYesterdayAmount[sale['amount']] ?? 0) + 1;
      } else {
        salesYesterdayAmount[sale['amount']] = 1;
      }
      if (kInitialCodes.any((e) => e['amount'] == sale['amount'])) {
        commissionYesterday += (sale['amount'] * 0.1);
      }
    }

    for (var sale in salesWeek) {
      if (salesWeekAmount.containsKey(sale['amount'])) {
        salesWeekAmount[sale['amount']] =
            (salesWeekAmount[sale['amount']] ?? 0) + 1;
      } else {
        salesWeekAmount[sale['amount']] = 1;
      }
      if (kInitialCodes.any((e) => e['amount'] == sale['amount'])) {
        commissionWeek += (sale['amount'] * 0.1);
      }
    }

    for (var sale in salesMonth) {
      if (salesMonthAmount.containsKey(sale['amount'])) {
        salesMonthAmount[sale['amount']] =
            (salesMonthAmount[sale['amount']] ?? 0) + 1;
      } else {
        salesMonthAmount[sale['amount']] = 1;
      }
      if (kInitialCodes.any((e) => e['amount'] == sale['amount'])) {
        commissionMonth += (sale['amount'] * 0.1);
      }
    }
  }

  Future<List<Map<String, dynamic>>> getTotalVolumePerOffer(int days) async {
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = getNormalDate(startDate);

    // Query: sum total per amount for the last `days` days
    final result = await SQLiteService().rawQueryInput('''
      SELECT amount, COUNT(*) as total
      FROM transactions
      WHERE date >= ?
        AND (status LIKE '%${TransactionStatuses.done}%' 
            OR status LIKE '%${TransactionStatuses.doneConfirmed}%'
            OR status = '${TransactionStatuses.advancedUssd}')
      GROUP BY amount
      ORDER BY total DESC
    ''', [startDateStr]);

    return result
        .map((row) => {
              'amount': row['amount'].toString(),
              'total': row['total'] ?? 0,
            })
        .toList();
  }

  @override
  void initState() {
    super.initState();
    getTotalVolumePerOffer(7).then((data) {
      setState(() {
        offerVolumes.addAll(data);
      });
    });
    getSales();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // drop down button to select time frame (week or mth )
        DropdownButtonFormField<String>(
          iconSize: 12,
          padding: const EdgeInsets.all(0),
          initialValue: _selectedTimeframe,
          items: const [
            DropdownMenuItem(value: 'week', child: Text('Week')),
            DropdownMenuItem(value: 'month', child: Text('Month')),
            DropdownMenuItem(value: 'year', child: Text('Year')),
          ],
          onChanged: (value) async {
            if (value == null) return;
            setState(() {
              _selectedTimeframe = value;
              offerVolumes.clear();
            });
            final days = value == 'week'
                ? 7
                : value == 'month'
                    ? 30
                    : 365;
            final data = await getTotalVolumePerOffer(days);
            setState(() {
              offerVolumes.addAll(data);
            });
            getSales();
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kBorderRadius),
            ),
            labelText: 'Timeframe',
          ),
        ),
        Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: PieChart(
                        PieChartData(
                          pieTouchData: PieTouchData(
                            touchCallback:
                                (FlTouchEvent event, pieTouchResponse) {
                              setState(() {
                                if (!event.isInterestedForInteractions ||
                                    pieTouchResponse == null ||
                                    pieTouchResponse.touchedSection == null) {
                                  touchedIndex = -1;
                                  return;
                                }
                                touchedIndex = pieTouchResponse
                                    .touchedSection!.touchedSectionIndex;
                              });
                            },
                          ),
                          borderData: FlBorderData(
                            show: false,
                          ),
                          sectionsSpace: 0,
                          centerSpaceRadius: 40,
                          sections: showingSections(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // sale bar info for touched index
            if (touchedIndex != -1 && offerVolumes.isNotEmpty)
              saleBarInfo(context, offerVolumes[touchedIndex]),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (var amount in offerVolumes)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  TransactionHistoryPage(
                                      query: amount["amount"].toString()),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            return CupertinoPageTransition(
                              primaryRouteAnimation: animation,
                              secondaryRouteAnimation: secondaryAnimation,
                              linearTransition: true,
                              child: child,
                            );
                          },
                        ),
                      );
                    },
                    child: saleBarInfo(context, amount),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Container saleBarInfo(BuildContext context, Map<String, dynamic> amount) {
    return Container(
      margin: const EdgeInsets.all(5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: kSectionColors[
              offerVolumes.toList().indexOf(amount) % kSectionColors.length],
          width: 2,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            'Ksh ${amount["amount"]}',
            style: TextStyle(
              color: kSectionColors[offerVolumes.toList().indexOf(amount) %
                  kSectionColors.length],
              // fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Day: Sh${Numbers.formatNumber(((salesDayAmount[int.parse((amount["amount"]).toString())] ?? 0) * int.parse((amount["amount"]).toString())).toInt())}',
            style: TextStyle(
              color: Theme.of(context).indicatorColor,
              // fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Yst: Sh${Numbers.formatNumber(((salesYesterdayAmount[int.parse((amount["amount"]).toString())] ?? 0) * int.parse((amount["amount"]).toString())).toInt())}',
            style: const TextStyle(
                // fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            'Wk: Sh${Numbers.formatNumber(((salesWeekAmount[int.parse((amount["amount"]).toString())] ?? 0) * int.parse((amount["amount"]).toString())).toInt())}',
            style: const TextStyle(
                // fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            'Mth: Sh${Numbers.formatNumber(((salesMonthAmount[int.parse((amount["amount"]).toString())] ?? 0) * int.parse((amount["amount"]).toString())).toInt())}',
            style: const TextStyle(
                // fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> showingSections() {
    final total = offerVolumes.fold<int>(
        0,
        (sum, item) =>
            sum + (item['total'] as int) * int.parse(item['amount']));
    return List.generate(offerVolumes.length, (i) {
      final isTouched = i == touchedIndex;
      final fontSize = isTouched ? 25.0 : 4.0;
      final radius = isTouched ? 60.0 : 50.0;
      final value = (offerVolumes[i]['total'] as int) *
          int.parse(offerVolumes[i]['amount']);
      final percent =
          total > 0 ? ((value / total) * 100).toStringAsFixed(0) : '0';
      return PieChartSectionData(
        color: kSectionColors[i % kSectionColors.length],
        value: value.toDouble(),
        title: '$percent%',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
        ),
      );
    });
  }
}

Widget Indicator({
  required Color color,
  required String text,
  bool isSquare = false,
}) {
  return Row(
    children: <Widget>[
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
          color: color,
        ),
      ),
      const SizedBox(
        width: 4,
      ),
      Text(text, style: const TextStyle(fontSize: 14)),
    ],
  );
}
