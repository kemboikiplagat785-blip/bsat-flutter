import 'package:flutter/material.dart';
import 'package:sim_data/sim_data.dart';

import '../../utils/constants.dart';

Future<SimCard?> chooseSim(
  BuildContext context,
  List<SimCard> sims, {
  bool isBoth = false,
}) {
  return showDialog<SimCard>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: kPagePadding),
            Center(child: Text("Select a sim card to use")),
            Padding(
              padding: const EdgeInsets.all(kPagePadding),
              child: Row(
                children: [
                  ...sims.map((s) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context, s);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kPrimaryColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.sim_card,
                                size: 14, color: kPrimaryColor),
                            const SizedBox(width: 4),
                            Text(s.displayName,
                                style: TextStyle(
                                    color: kPrimaryColor,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (isBoth)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context, -1);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isBoth
                              ? kPrimaryColor.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isBoth
                                  ? kPrimaryColor
                                  : kGrayColor.withOpacity(0.2)),
                        ),
                        child: Text('Both',
                            style: TextStyle(
                                color: isBoth ? kPrimaryColor : kGrayColor,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
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
