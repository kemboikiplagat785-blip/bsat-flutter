import 'package:bsat/screens/tasks/edit_task.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';

Widget taskListItem(
  BuildContext context,
  String codeToRun,
  String startDate,
  String endDate,
  int id,

  // function
  Function callBackFunction,
) {
  // var textTheme = Theme.of(context).textTheme;

  return GestureDetector(
    child: Container(
      padding: kPagePaddingInsets,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            codeToRun,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(
            height: kPagePadding / 2,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("$startDate - $endDate"),
              IconButton(
                onPressed: () {
                  Navigator.of(context)
                      .push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          EditTaskPage(taskId: id),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                        // Define your custom animation here
                        // return FadeTransition(opacity: animation, child: child);
                        return CupertinoPageTransition(
                          primaryRouteAnimation: animation,
                          secondaryRouteAnimation: secondaryAnimation,
                          linearTransition: true,
                          child: child,
                        );
                      },
                    ),
                  )
                      .then((value) {
                    // if (value != null) {
                    callBackFunction();
                    // }
                  });
                },
                icon: Icon(
                  Icons.edit_note_sharp,
                  color: Theme.of(context).indicatorColor,
                ),
              )
            ],
          ),
        ],
      ),
    ),
  );
}
