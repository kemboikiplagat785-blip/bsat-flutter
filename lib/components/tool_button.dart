import 'package:flutter/material.dart';

import '../utils/constants.dart';

Widget toolButton(Function onTap, Icon icon, String text, BuildContext context,
    {bool withBorder = false,
    Color? accentColor,
    String? otherText,
    int? otherTextSize, int? textSize,}) {
  return GestureDetector(
    onTap: () => onTap(),
    child: Container(
      padding: kPagePaddingInsets / 3,
      decoration: BoxDecoration(
        color: accentColor != null
            ? accentColor.withOpacity(.2)
            : Theme.of(context).cardColor,
        border: Border.all(
          color: withBorder ? kDullColor : Colors.transparent,
          width: .5,
        ),
        borderRadius: BorderRadius.circular(kBorderRadius / 2),
        // color: kLightColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon(iconData),
          icon,
          if (text.isNotEmpty) const SizedBox(width: kPagePadding / 2),
          if (text.isNotEmpty)
            Text(
              text,
              style: TextStyle(
                fontWeight:
                    accentColor != null ? FontWeight.bold : FontWeight.normal,
                fontSize: textSize?.toDouble() ?? (accentColor != null ? 14 : null),
                color: accentColor,
              ),
            ),
          if (otherText != null)
            Padding(
              padding: const EdgeInsets.only(left: kPagePadding / 2),
              child: Text(
                otherText,
                style: TextStyle(
                  fontSize: otherTextSize?.toDouble() ?? 13,
                  color: accentColor ?? kDullColor,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
