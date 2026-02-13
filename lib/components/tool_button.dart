import 'package:flutter/material.dart';

import '../services/shared_preferences_service.dart';
import '../utils/constants.dart';

Widget toolButton(
  Function onTap,
  Icon icon,
  String text,
  BuildContext context, {
  bool withBorder = false,
  Color? accentColor,
  String? otherText,
  int? otherTextSize,
  int? textSize,
}) {
  return FutureBuilder<String?>(
    future: SharedPreferencesService().getThemeMode(),
    builder: (context, snapshot) {
      final isLightMode = (snapshot.data ?? "light") == "light";
      return GestureDetector(
        onTap: () => onTap(),
        child: Container(
          padding: kPagePaddingInsets / 3,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              bottom: BorderSide(
                // color: Theme.of(context).hintColor,
                color: Colors.black.withOpacity(0.9),
                width: 1,
              ),
              right: BorderSide(
                // color: Theme.of(context).hintColor,
                color: Colors.black.withOpacity(0.9),
                width: 1,
              ),
            ),
            // : null,
            // boxShadow: withBorder
            //     ? [
            //         BoxShadow(
            //           color: Theme.of(context).hintColor.withOpacity(0.9),
            //           blurRadius: 0,
            //           offset: const Offset(1, 1),
            //         ),
            //         // BoxShadow(
            //         //   color: Theme.of(context).hintColor.withOpacity(0.3),
            //         //   blurRadius: 0,
            //         //   offset: const Offset(-1, -1),
            //         // ),
            //       ]
            //     : null,
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
                    fontWeight: accentColor != null
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: textSize?.toDouble() ??
                        (accentColor != null ? 14 : null),
                    color: isLightMode ? kSecondaryColor : accentColor,
                  ),
                ),
              if (otherText != null)
                Padding(
                  padding: const EdgeInsets.only(left: kPagePadding / 2),
                  child: Text(
                    otherText,
                    style: TextStyle(
                      // fontWeight: FontWeight.bold,
                      fontSize: otherTextSize?.toDouble() ?? 13,
                      color: accentColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
