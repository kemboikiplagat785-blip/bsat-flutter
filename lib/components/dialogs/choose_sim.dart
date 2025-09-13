import 'package:flutter/material.dart';
import 'package:sim_data/sim_data.dart';

import '../../utils/constants.dart';

Future<SimCard?> chooseSim(
  BuildContext context,
  List<SimCard> sims,
) {
  return showDialog<SimCard>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(
          'Choose sim card',
          style: const TextStyle(
              // color: kDullColor,
              ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Select a sim card to use"),
            Container(
              padding: kPagePaddingInsets,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(kBorderRadius),
              ),
              child: Row(
                children: sims.map((s) {
                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context, s);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sim_card_rounded,
                            size: 40,
                            color: kPrimaryColor,
                          ),
                          const SizedBox(height: kPagePadding / 2),
                          Text(s.displayName, style: TextStyle(color: kPrimaryColor.withValues(alpha: 0.7)),),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          )
        ],
      );
    },
  );
}
