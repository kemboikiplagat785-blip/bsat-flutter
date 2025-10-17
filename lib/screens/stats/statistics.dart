import 'package:bsat/screens/stats/daily_value_performance_over_time.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import './airtime_per_day.dart';
import './commission.dart';
import 'sales_volume_per_offer.dart';
import '../../components/header.dart';
import '../../utils/constants.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {

  @override
  void initState() {
    super.initState();
    // seperateAmounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, 'Business Insights'),
            const SizedBox(height: kPagePadding),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Text('Commission (Ksh)'),
            ),
            const SizedBox(height: kPagePadding / 4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Container(
                padding: const EdgeInsets.all(kPagePadding),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(0),
                      child: CommissionGraph(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: kPagePadding),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Text('Airtime usage (Ksh)'),
            ),
            const SizedBox(height: kPagePadding / 4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Container(
                padding: const EdgeInsets.all(kPagePadding),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(0),
                      child: AirtimePerDay(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: kPagePadding),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Text('Daily customers'),
            ),
            const SizedBox(height: kPagePadding / 4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Container(
                padding: const EdgeInsets.all(kPagePadding),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: kPagePadding),

                    Padding(
                      padding: const EdgeInsets.all(0),
                      child: ValuePerformanceOverTime(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: kPagePadding),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Text('Sales (Ksh)'),
            ),
            const SizedBox(height: kPagePadding / 4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Container(
                padding: const EdgeInsets.all(kPagePadding),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: kPagePadding),

                    Padding(
                      padding: const EdgeInsets.all(0),
                      child: SalesVolumePerOffer(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: kPagePadding * 2),
          ],
        ),
      ),
    );
  }
}
