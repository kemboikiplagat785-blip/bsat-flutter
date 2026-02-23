import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Widget deviceCard({
  required BuildContext context,
  required String deviceName,
  String? deviceDetails,
  String? androidVersion,
  String? model,
  int? batteryLevel,
  required IconData iconData,
  Widget? trailing,
  Widget? delete,
  Widget? footer,
}) {
  return Container(
    padding: const EdgeInsets.all(kPagePadding),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8.0),
      color: Theme.of(context).cardColor,
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(iconData, size: 40.0, color: kPrimaryColor),
                const SizedBox(width: kPagePadding / 1.5),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: kPrimaryColor,
                        // fontSize: 16.0,
                      ),
                    ),
                    if (deviceDetails != null)
                      Text(
                        deviceDetails,
                        style: TextStyle(
                          // fontSize: 14.0,
                        ),
                      ),
                    if (model != null)
                      Text(
                        "Model: $model",
                        style: TextStyle(
                          fontSize: 12.0,
                        ),
                      ),
                    if (androidVersion != null)
                      Text(
                        "Android: $androidVersion",
                        style: TextStyle(
                          fontSize: 12.0,
                        ),
                      ),
                    if (batteryLevel != null)
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.battery_charging,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "$batteryLevel%",
                            style: TextStyle(
                              fontSize: 12.0,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                // const SizedBox(width: kPagePadding / 4),
              ],
            ),
            if (trailing != null) ...[
              const SizedBox(height: 8.0),
              trailing,
            ],
          ],
        ),
        if (footer != null) footer,
      ],
    ),
  );
}
