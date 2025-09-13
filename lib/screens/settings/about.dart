import 'package:bsat/components/header.dart';
import 'package:bsat/components/hero.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String appVersion = '';

  @override
  void initState() {
    super.initState();
    getAppVersion().then((value) {
      setState(() {
        appVersion = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, 'About BSAT'),
            myHeroWidget(context),
            Padding(
              padding: kPagePaddingInsets,
              child: Container(
                padding: kPagePaddingInsets,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About BSAT (Bingwa Sokoni Automation Toolkit)',
                    ),
                    const SizedBox(height: kPagePadding / 2),
                    Text(
                      'BSAT is a mobile application that helps you automate and monitor Bingwa Sokoni and other USSD tasks.',
                    ),
                    Text(
                      'BSAT is not affiliated with Safaricom or M-Pesa. It is a personal project by the developer.',
                    ),
                    const SizedBox(height: kPagePadding),
                    Text('Version: $appVersion'),
                    const SizedBox(height: kPagePadding),
                    Text('Inqueries & Customer Support: Timeon Tony'),
                    const SizedBox(height: kPagePadding / 2),
                    Text('Call: 0742342297, WhatsApp: 0795559924'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
