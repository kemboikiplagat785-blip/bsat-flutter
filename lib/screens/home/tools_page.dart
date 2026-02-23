import 'package:bsat/components/dialogs/forward_text.dart';
import 'package:bsat/screens/dialpad.dart';
import 'package:bsat/screens/foward_sms.dart';
import 'package:bsat/screens/online_management/online_management.dart';
import 'package:bsat/screens/replies/replies.dart';
import 'package:bsat/screens/tasks/tasks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/button_descriptive.dart';
import '../../components/header.dart';
import '../../components/section_header.dart';
import '../../utils/constants.dart';
import '../offers/offers.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              header(context, "Tools", hideBack: true),
              buttonDescriptive(
                context,
                title: 'Add, edit, or delete offers',
                subtitle: 'Manage offers',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const OffersPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.tag,
                  color: kIndigoColor,
                ),
              ),
              // scheduler
              buttonDescriptive(
                context,
                title: 'Schedule transactions for later',
                subtitle: 'Scheduler',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TaskManagerPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.calendar,
                  color: kPrimaryColor,
                ),
              ),
              // dialpad
              buttonDescriptive(
                context,
                title: 'Make transaction manually',
                subtitle: 'Dialpad',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => DialPadScreen(),
                    ),
                  );
                },
                icon: Icon(
                  Icons.dialpad,
                  color: kErrorColor,
                ),
              ),
              // edit automated relies
              buttonDescriptive(
                context,
                title: 'Edit or manage your automated rules and relies',
                subtitle: 'Automated replies',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const RepliesPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.text_bubble,
                  color: kWarningColor,
                ),
              ),

              const SizedBox(height: kPagePadding * 2),
              sectionHeader('Forwarding messages'),

              // sms forwarding
              buttonDescriptive(
                context,
                title: 'Set up SMS forwarding to another number',
                subtitle: 'OFFLINE SMS forwarding',
                onTap: () {
                  // showForwardTextDialog(context, message, toForward)
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ForwardSmsPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.arrow_right_arrow_left,
                  color: kPrimaryColor,
                ),
              ),

              // online sms forwarding
              buttonDescriptive(
                context,
                title: 'Set up online SMS forwarding to another device',
                subtitle: 'ONLINE SMS forwarding',
                onTap: () {
                  // showForwardTextDialog(context, message, toForward)
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const OnlineManagementScreen(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.arrow_right_arrow_left,
                  color: kIndigoColor,
                ),
              ),
              const SizedBox(height: kPagePadding * 7),
            ],
          ),
        ),
      ),
    );
  }
}
