import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';

Widget header(BuildContext context, String title, {bool isDashboard = false}) {
  var textTheme = Theme.of(context).textTheme;
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.only(
        bottomLeft: Radius.circular(kBorderRadius),
        bottomRight: Radius.circular(kBorderRadius),
      ),
      color: Theme.of(context).cardColor,
    ),
    child: Column(
      children: [
        const SizedBox(height: kPagePadding * 2),
        Padding(
          padding: kPagePaddingInsets,
          child: Row(
            children: [
              isDashboard
                ? const SizedBox()
                : GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(
                  CupertinoIcons.back,
                  size: 14,
                ),
              ),
              const SizedBox(width: kPagePadding),
              Text(
                title,
                style: textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
