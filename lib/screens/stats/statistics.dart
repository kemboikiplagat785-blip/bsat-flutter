import 'package:bsat/screens/stats/daily_value_performance_over_time.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import './airtime_per_day.dart';
import './commission.dart';
import 'sales_volume_per_offer.dart';
import '../../components/header.dart';
import '../../utils/constants.dart';

class StatisticsPage extends StatefulWidget {
  final bool isDashboard;
  const StatisticsPage({super.key, this.isDashboard = false});

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
            header(context, 'Business Insights',
                hideBack: widget.isDashboard),
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
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  image: DecorationImage(
                    image: AssetImage(
                      'assets/images/mesh_distorted.png',
                    ),
                    fit: BoxFit.cover,
                    opacity: 0.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).hintColor.withOpacity(0.9),
                      blurRadius: 0,
                      offset: const Offset(3, 3),
                    ),
                    BoxShadow(
                      color: Theme.of(context).hintColor.withOpacity(0.9),
                      blurRadius: 0,
                      offset: const Offset(-1, -1),
                    ),
                  ],
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
              child: Text('Commission (Ksh)'),
            ),
            const SizedBox(height: kPagePadding / 4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Container(
                padding: const EdgeInsets.all(kPagePadding),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  image: DecorationImage(
                    image: AssetImage(
                      'assets/images/mesh_distorted.png',
                    ),
                    fit: BoxFit.cover,
                    opacity: 0.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).hintColor.withOpacity(0.9),
                      blurRadius: 0,
                      offset: const Offset(3, 3),
                    ),
                    BoxShadow(
                      color: Theme.of(context).hintColor.withOpacity(0.9),
                      blurRadius: 0,
                      offset: const Offset(-1, -1),
                    ),
                  ],
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
              child: Text('Daily customers'),
            ),
            const SizedBox(height: kPagePadding / 4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Container(
                padding: const EdgeInsets.all(kPagePadding),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  image: DecorationImage(
                    image: AssetImage(
                      'assets/images/mesh_distorted.png',
                    ),
                    fit: BoxFit.cover,
                    opacity: 0.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).hintColor.withOpacity(0.9),
                      blurRadius: 0,
                      offset: const Offset(3, 3),
                    ),
                    BoxShadow(
                      color: Theme.of(context).hintColor.withOpacity(0.9),
                      blurRadius: 0,
                      offset: const Offset(-1, -1),
                    ),
                  ],
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
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  image: DecorationImage(
                    image: AssetImage(
                      'assets/images/mesh_distorted.png',
                    ),
                    fit: BoxFit.cover,
                    opacity: 0.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).hintColor.withOpacity(0.9),
                      blurRadius: 0,
                      offset: const Offset(3, 3),
                    ),
                    BoxShadow(
                      color: Theme.of(context).hintColor.withOpacity(0.9),
                      blurRadius: 0,
                      offset: const Offset(-1, -1),
                    ),
                  ],
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
            const SizedBox(height: kPagePadding * 7),
          ],
        ),
      ),
    );
  }
}
