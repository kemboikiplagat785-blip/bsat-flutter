import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';

InkWell buttonDescriptive(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Function() onTap,
  required Icon icon,
}) {
  return InkWell(
    onTap: onTap,
    child: Container(
      padding: kPagePaddingInsets,
      margin: const EdgeInsets.only(
        top: kPagePadding,
        left: kPagePadding,
        right: kPagePadding,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: kPagePadding / 2),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: kPagePadding / 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    // fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            size: 30,
          ),
        ],
      ),
    ),
  );
}
