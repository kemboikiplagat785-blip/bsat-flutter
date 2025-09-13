import 'package:flutter/services.dart';
import 'package:sim_data/sim_data.dart';

Future<SimData?> getSimCardsData() async {
  try {
    SimData simData = await SimDataPlugin.getSimData();
    return simData;
  } on PlatformException catch (e) {
    return null;
  }
}
