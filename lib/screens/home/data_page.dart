import 'package:bsat/components/button_descriptive.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/components/section_header.dart';
import 'package:bsat/screens/inbox.dart';
import 'package:bsat/screens/offers/offers.dart';
import 'package:bsat/screens/replies/replies.dart';
import 'package:bsat/screens/stats/statistics.dart';
import 'package:bsat/screens/transactions/transaction_history.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../blacklist.dart';
import '../clients/clients.dart';
import '../clients/sync_data.dart';

class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              header(context, "My data", hideBack: true),
              buttonDescriptive(
                context,
                title: 'Recent transactons',
                subtitle: 'History',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TransactionHistoryPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.clock,
                  color: kPrimaryColor,
                ),
              ),
              buttonDescriptive(
                context,
                title: 'Airtime usage, commission earned, sales volumes, etc',
                subtitle: 'Business insights',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const StatisticsPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.graph_circle,
                  color: kIndigoColor,
                ),
              ),
              // inbox
              buttonDescriptive(
                context,
                title: 'View your MPESA and Safaricom inbox',
                subtitle: 'Inbox',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const InboxPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.text_bubble,
                  color: kPrimaryColor,
                ),
              ),
              const SizedBox(height: kPagePadding * 2),
              sectionHeader("Clients"),
              // clients
              buttonDescriptive(
                context,
                title: 'View and manage your clients',
                subtitle: 'My clients',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ClientsPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.person_2,
                  color: kErrorColor,
                ),
              ),
              // blacklisted clients
              buttonDescriptive(
                context,
                title: 'View and manage your blacklisted clients',
                subtitle: 'Blacklisted clients',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => BlacklistPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.person_crop_circle_badge_xmark,
                  color: kWarningColor,
                ),
              ),
              // sync data
              buttonDescriptive(
                context,
                title: 'Sync client data',
                subtitle: 'Get/export all clients and contacts data',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SyncDataPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.arrow_2_circlepath,
                  color: kPrimaryColor,
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
