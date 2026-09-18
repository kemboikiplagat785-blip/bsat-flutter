import 'package:another_telephony/telephony.dart';
import 'package:flutter/services.dart';

Future<List<SubscriptionInfo>?> getSimCardsData() async {
  try {
    return await Telephony.instance.getSubscriptionList();
  } on PlatformException {
    return null;
  }
}
