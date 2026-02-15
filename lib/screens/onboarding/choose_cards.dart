import 'package:bsat/components/dialogs/check_offers_dialog.dart';
import 'package:bsat/screens/home/dashboard/dashboard.dart';
import 'package:bsat/screens/home/home.dart';
import 'package:bsat/screens/offers/offers.dart';
import 'package:bsat/screens/settings/settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sim_data/sim_data.dart';

import '../../components/dialogs/must_use_both_sims_dialog.dart';
import '../../components/dialogs/show_error_dialog.dart';
import '../../components/hero.dart';
import '../../services/shared_preferences_service.dart';
import '../../services/sqlite_service.dart';
import '../../utils/constants.dart';

class ChooseCardPage extends StatefulWidget {
  const ChooseCardPage({super.key});

  @override
  State<ChooseCardPage> createState() => _ChooseCardPageState();
}

class _ChooseCardPageState extends State<ChooseCardPage> {
  List<SimCard> sims = [];

  bool error = false;

  final _sharedPreferencesService = SharedPreferencesService();
  int _fromSim = -1;
  int _dialSim = -1;

  bool _fromBothSims = true;

  final _sqliteService = SQLiteService();

  @override
  void initState() {
    super.initState();

    getAndProcessCards();
    _sharedPreferencesService.setRunningStatus(true);
  }

  void getAndProcessCards() {
    SimDataPlugin.getSimData().then((value) {
      setState(() {
        sims = value.cards;
        sims = value.cards;
        // debugPrint("Got cards");
      });
    });
  }

  Future<void> addAllCodesToDatabase() async {
    for (var i in kInitialCodes) {
      _sqliteService.insertStuff(
        {
          'amount': i["amount"],
          'code': i["code"],
          'fromSim': -1,
          'dialSim': _dialSim,
          'canRetry': 1,
          'enabled': 1,
        },
        'ussdCodes',
      );
    }

    for (var i in kNoAutoretryCodes) {
      _sqliteService.insertStuff(
        {
          'amount': i["amount"],
          'code': i["code"],
          'fromSim': -1,
          'dialSim': _dialSim,
          // 'canRetry': 0,
          'canRetry': 1,
          'enabled': 1,
        },
        'ussdCodes',
      );
    }

    await _sharedPreferencesService.setSmsRunning(true);
    await _sharedPreferencesService.setDataRunning(true);
    await _sharedPreferencesService.setCanAutoRetryData(true);
    await _sharedPreferencesService.setRetryMinutes(3);
  }

  @override
  Widget build(BuildContext context) {
    // getAndProcessCards();
    var size = MediaQuery.of(context).size;
    var textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          myHeroWidget(context),
          const Spacer(
            flex: 3,
          ),
          Padding(
            padding: kPagePaddingInsets,
            child: Container(
              padding: kPagePaddingInsets,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(kBorderRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Automate money received from (Can switch later)',
                    style: TextStyle(
                      // color: error ? kErrorColor : kDullColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: kPagePadding),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: sims.map((s) {
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    // _fromBothSims = false;
                                    // _fromSim = s.subscriptionId;
                                  });
                                  // mustUseBothSimsDialog(context);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                      right: kPagePadding / 2),
                                  child: Column(
                                    children: [
                                      Text(
                                        s.displayName,
                                        style: TextStyle(
                                          color: s.subscriptionId == _fromSim
                                              ? kPrimaryColor
                                              : Theme.of(context)
                                                  .indicatorColor,
                                        ),
                                      ),
                                      const SizedBox(height: kPagePadding / 2),
                                      Icon(
                                        Icons.sim_card_rounded,
                                        size: 40,
                                        color: s.subscriptionId == _fromSim
                                            ? kPrimaryColor
                                            : kGrayColor,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const Text(
                            'Both',
                            // style: TextStyle(color: kDullColor),
                          ),
                          Checkbox(
                            activeColor: kPrimaryColor,
                            value: _fromBothSims,
                            onChanged: (value) {
                              setState(() {
                                _fromBothSims = true;
                                _fromSim = -1;
                                // _fromBothSims = value ?? false;
                                // _fromSim = -1;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding * 2),
                  Text(
                    'Recommend using (Can switch later)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      // color: error ? kErrorColor : Theme.of(context).indicatorColor,
                    ),
                  ),
                  const SizedBox(height: kPagePadding),
                  Row(
                    // children: cards,
                    children: sims.map((s) {
                      return Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _dialSim = s.subscriptionId;
                            });
                          },
                          child: Column(
                            children: [
                              Text(
                                s.displayName,
                                style: TextStyle(
                                  color: s.subscriptionId == _dialSim
                                      ? kPrimaryColor
                                      : Theme.of(context).indicatorColor,
                                ),
                              ),
                              const SizedBox(height: kPagePadding / 2),
                              Icon(
                                Icons.sim_card_rounded,
                                size: 40,
                                color: s.subscriptionId == _dialSim
                                    ? kPrimaryColor
                                    : kGrayColor,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  // const SizedBox(height: kPagePadding * 2),
                ],
              ),
            ),
          ),
          const Spacer(),
          Hero(
            tag: 'next-btn',
            child: InkWell(
              onTap: () async {
                if (_dialSim < 0) {
                  showErrorDialog(
                    context,
                    'No dial sim selected',
                    'Please select a sim card to recommend offers.',
                  );
                  return;
                }
                await checkOffersDialog(context);
                addAllCodesToDatabase().then((value) {
                  Navigator.of(context)
                      .push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          const OffersPage(),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                        // Define your custom animation here
                        // return FadeTransition(opacity: animation, child: child);
                        return CupertinoPageTransition(
                          primaryRouteAnimation: animation,
                          secondaryRouteAnimation: secondaryAnimation,
                          linearTransition: true,
                          child: child,
                        );
                      },
                    ),
                  )
                      .then(
                    (value) {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  const HomePage(),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            // Define your custom animation here
                            // return FadeTransition(opacity: animation, child: child);
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
                  );
                });
              },
              child: Container(
                padding: kPagePaddingInsets,
                width: size.width - (kPagePadding * 2),
                child: Center(
                  child: Text(
                    '$interpunct $interpunct $interpunct $interpunct Next',
                    style: textTheme.titleLarge!.merge(
                      const TextStyle(
                        // color: kPrimaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: kPagePadding * 3),
        ],
      ),
    );
  }
}
