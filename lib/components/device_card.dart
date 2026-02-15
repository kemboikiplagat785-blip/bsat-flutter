import 'package:bsat/utils/constants.dart';
import 'package:flutter/material.dart';

Widget deviceCard({
  required BuildContext context,
  required String deviceName,
  required String deviceDetails,
  required IconData iconData,
  Widget? trailing,
  Widget? delete,
}) {
  return Container(
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8.0),
      color: Theme.of(context).cardColor,
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(iconData, size: 40.0, color: kIndigoColor),
            const SizedBox(width: kPagePadding / 1.5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    // fontSize: 16.0,
                  ),
                ),
                Text(
                  deviceDetails,
                  style: TextStyle(
                    color: Colors.grey[600],
                    // fontSize: 14.0,
                  ),
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
  );
}
