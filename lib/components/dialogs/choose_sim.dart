import 'package:another_telephony/telephony.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<SubscriptionInfo?> chooseSim(
  BuildContext context,
  List<SubscriptionInfo> sims, {
  bool isBoth = false,
}) {
  return showDialog<SubscriptionInfo>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: kPagePadding),
            const Center(child: Text("Select a sim card to use")),
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
                          color: kPrimaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kPrimaryColor),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.sim_card,
                              size: 14,
                              color: kPrimaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              s.displayName ?? 'SIM',
                              style: TextStyle(
                                color: kPrimaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (isBoth)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kPrimaryColor),
                        ),
                        child: const Text(
                          'Both',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
