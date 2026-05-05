import 'package:flutter/material.dart';

class SimCardIconWithNumber extends StatelessWidget {
  final int number;
  const SimCardIconWithNumber({super.key, required this.number});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          Icons.sim_card,
          size: 25,
          color: Theme.of(context).cardColor,
        ),
        Positioned(
          bottom: 4,
          child: Text(
            "$number",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              // color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
