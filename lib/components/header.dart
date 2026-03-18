import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';

Widget header(BuildContext context, String title, {bool hideBack = false, VoidCallback? onMoreOptions}) {
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
              hideBack
                  ? const SizedBox()
                  : Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                        // border: Border.all(
                        //   color: kIndigoColor,
                        //   width: 2,
                        // ),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          CupertinoIcons.back,
                          size: 14,
                        ),
                      ),
                    ),
              const SizedBox(width: kPagePadding),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.titleLarge,
                ),
              ),
              if (onMoreOptions != null)
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: onMoreOptions,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
