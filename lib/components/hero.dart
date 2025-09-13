import 'package:flutter/material.dart';

import '../utils/constants.dart';

Widget myHeroWidget(BuildContext context) {
  return Hero(
    tag: 'title',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/icons/icon.png',
          height: 80,
        ),
        const SizedBox(height: kPagePadding,),
        Center(
          child: Text(
            'BSAT',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Text(
          'Bingwa Sokoni Automation Toolkit',
        ),
      ],
    ),
  );
}
