import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

class ComingSoonPage extends StatefulWidget {
  const ComingSoonPage({super.key});

  @override
  State<ComingSoonPage> createState() => _ComingSoonPageState();
}

class _ComingSoonPageState extends State<ComingSoonPage> {
  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            // padding: const EdgeInsets.only(bottom: kPagePadding),
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/card_bg.png'),
                fit: BoxFit.cover,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(kBorderRadius),
                bottomRight: Radius.circular(kBorderRadius),
              ),
              color: kLightColor,
            ),
            child: Column(
              children: [
                const SizedBox(height: kPagePadding * 2),
                Padding(
                  padding: kPagePaddingInsets,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          CupertinoIcons.back,
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: kPagePadding / 2),
                      Text(
                        'Coming soon',
                        style: textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 3),
          Center(
            child: IconButton(
              onPressed: () {
                // SQLiteService().deleteStuff(4, 'payments');
              },
              icon: Icon(CupertinoIcons.tortoise,
                  color: Theme.of(context).indicatorColor, size: 80),
            ),
          ),
          const Spacer(),
          const Center(
              child:
                  Text('Don\'t fret, we are working on adding this feature.')),
          const Spacer(flex: 5),
        ],
      ),
    );
  }
}
