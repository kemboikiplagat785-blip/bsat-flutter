import 'package:flutter/material.dart';

import '../utils/constants.dart';

Widget sectionHeader(String title) {
  return Row(
    children: [
      Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(kBorderRadius / 2),
          border: Border(
            right: BorderSide(
              color: kIndigoColor,
              width: 1,
            ),
            bottom: BorderSide(
              color: kIndigoColor,
              width: 1,
            ),
          ),
        ),
        // width: double.infinity,
        margin: const EdgeInsets.only(left: kPagePadding),
        padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
        child: Text(
          title,
          style: TextStyle(
            // fontSize: 18,
            fontWeight: FontWeight.bold,

            // color: Colors.grey.shade700,
          ),
        ),
      ),
    ],
  );
}
