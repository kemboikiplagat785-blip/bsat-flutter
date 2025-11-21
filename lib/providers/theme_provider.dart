import 'package:bsat/services/shared_preferences_service.dart';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

class ThemeProvider with ChangeNotifier {
  ThemeData _currentTheme = lightTheme;

  ThemeData get currentTheme => _currentTheme;

  ThemeProvider() {
    _loadTheme();
  }

  final _sharedPreferenceService = SharedPreferencesService();

  void _loadTheme() async {
    var selectedTheme = await _sharedPreferenceService.getThemeMode();

    // debugPrint("Selected Theme: $selectedTheme");

    if (selectedTheme == "dark") {
      _currentTheme = darkTheme;
    } else if (selectedTheme == "brown") {
      _currentTheme = brownTheme;
    } else if (selectedTheme == "light") {
      _currentTheme = lightTheme;
    } else if (selectedTheme == "indigo") {
      _currentTheme = indigoTheme;
    } else if (selectedTheme == "darkPurple") {
      _currentTheme = darkPurpleTheme;
    } else if (selectedTheme == "pink") {
      _currentTheme = pinkTheme;
    } else if (selectedTheme == "blackAndWhite") {
      _currentTheme = blackAndWhiteTheme;
    } else {
      // var brightness = WidgetsBinding.instance.window.platformBrightness;
      // if (brightness == Brightness.dark) {
      _currentTheme = darkPurpleTheme;
      _sharedPreferenceService.setThemeMode("darkPurple");
      // } else {
      //   _currentTheme = lightTheme;
      // }
    }

    notifyListeners();
  }

  void setDarkTheme() async {
    _currentTheme = darkTheme;
    await _sharedPreferenceService.setThemeMode("dark");
    notifyListeners();
  }

  void setlightTheme() async {
    _currentTheme = lightTheme;
    await _sharedPreferenceService.setThemeMode("light");
    notifyListeners();
  }

  void setBrownTheme() async {
    _currentTheme = brownTheme;
    await _sharedPreferenceService.setThemeMode("brown");
    notifyListeners();
  }

  void setIndigoColor() async {
    _currentTheme = indigoTheme;
    await _sharedPreferenceService.setThemeMode("indigo");
    notifyListeners();
  }

  void setDarkPurpleTheme() async {
    _currentTheme = darkPurpleTheme;
    await _sharedPreferenceService.setThemeMode("darkPurple");
    notifyListeners();
  }

  void setPinkTheme() async {
    _currentTheme = pinkTheme;
    await _sharedPreferenceService.setThemeMode("pink");
    notifyListeners();
  }

  void setBlackAndWhiteTheme() async {
    _currentTheme = blackAndWhiteTheme;
    await _sharedPreferenceService.setThemeMode("blackAndWhite");
    notifyListeners();
  }
}
