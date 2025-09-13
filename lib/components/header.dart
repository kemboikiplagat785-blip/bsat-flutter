import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';

Widget header(BuildContext context, String title) {
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
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  CupertinoIcons.back,
                  size: 14,
                ),
              ),
              const SizedBox(width: kPagePadding / 2),
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
