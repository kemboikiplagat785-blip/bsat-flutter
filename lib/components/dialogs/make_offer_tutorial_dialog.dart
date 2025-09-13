import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<void> makeOfferTutorialDialog(BuildContext context) {
  // var sqliteService = SQLiteService();
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('How to make offers'),
        // title: Text('How to make an offer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'But first, what are offers ...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('Consider the following packages offered by person X.'),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: Image.asset('assets/images/tutorial-offers.png'),
                ),
              ),
              const Text('Offers are the packages you advertise to your customers.'),
              const SizedBox(height: kPagePadding / 4),
              const Text(
                'How to make them',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: Image.asset('assets/images/tutorial-message.png'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: Image.asset('assets/images/tutorial-ussd-fields.png'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '1. Amount you expect to receive.',
                  style: TextStyle(color: kPrimaryColor),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '2. The sim card that will receive the amount indicated above.',
                  style: TextStyle(color: Theme.of(context).indicatorColor),
                ),
              ),
              const Text(
                  'You can use both sim cards if they both have the same offers.'),
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '3. USSD code to dial.',
                  style: TextStyle(color: kErrorColor),
                ),
              ),
              const Text(
                  'Remeber to use the letter "n" in place of the recipient\'s number, e.g. *180*5*2*n*6*1#'),
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '4. The sim card that will be used to recommend the offer.',
                  style: TextStyle(color: kWarningColor),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
