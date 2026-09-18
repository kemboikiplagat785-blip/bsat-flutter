import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'package:google_fonts/google_fonts.dart';

var lightTheme = ThemeData(
  // colorScheme: ColorScheme.fromSeed(seedColor: kIndigoColor),
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: kBgColor,
  cardColor: kLightColor.withValues(alpha: .5),
  hintColor: kSecondaryColor,
  focusColor: kSecondaryColor,
  textTheme: GoogleFonts.karlaTextTheme().apply(
      // bodyColor: kIndigoColor,
      ),
  tabBarTheme: TabBarThemeData(indicatorColor: kIndigoColor),
  // brightness: Brightness.dark
);

var darkTheme = ThemeData(
  // colorScheme: ColorScheme.fromSeed(seedColor: kIndigoColor),
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: kSecondaryColor,
  primaryColor: kLightColor,
  cardColor: kLightColor.withValues(alpha: .1),
  hintColor: kLightColor.withValues(alpha: .7),
  focusColor: kLightColor.withValues(alpha: .7),

  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withValues(alpha: .7)),
  brightness: Brightness.dark,
  tabBarTheme: TabBarThemeData(indicatorColor: kLightColor),
);

var brownTheme = ThemeData(
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: kBrownBackground,
  primaryColor: kLightColor,
  cardColor: kLightColor.withValues(alpha: .1),
  hintColor: kLightColor.withValues(alpha: .7),
  focusColor: kLightColor.withValues(alpha: .7),
  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withValues(alpha: .7)),
  brightness: Brightness.dark,
  tabBarTheme: TabBarThemeData(indicatorColor: kLightColor),
);

var indigoTheme = ThemeData(
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: kIndigoColor.withAlpha(150),
  primaryColor: kLightColor,
  cardColor: kLightColor.withValues(alpha: .1),
  hintColor: kLightColor.withValues(alpha: .7),
  focusColor: kLightColor.withValues(alpha: .7),
  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withValues(alpha: .7)),
  brightness: Brightness.dark,
  tabBarTheme: TabBarThemeData(indicatorColor: kLightColor),
);

var darkPurpleTheme = ThemeData(
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: Color(0xFF190b28),
  primaryColor: kLightColor,
  cardColor: kLightColor.withValues(alpha: .1),
  hintColor: kLightColor.withValues(alpha: .7),
  focusColor: kLightColor.withValues(alpha: .7),
  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withValues(alpha: .7)),
  brightness: Brightness.dark,
  tabBarTheme: TabBarThemeData(indicatorColor: kLightColor),
);

var pinkTheme = ThemeData(
  // colorScheme: ColorScheme.fromSeed(seedColor: kIndigoColor),
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: Color.fromARGB(255, 82, 23, 52),
  primaryColor: kLightColor,
  cardColor: kLightColor.withValues(alpha: .1),
  hintColor: kLightColor.withValues(alpha: .7),
  focusColor: kLightColor.withValues(alpha: .7),

  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withValues(alpha: .7)),
  brightness: Brightness.dark,
  tabBarTheme: TabBarThemeData(indicatorColor: kLightColor),
);

// black background. force everything to white or black
var blackAndWhiteTheme = ThemeData(
  // colorScheme: ColorScheme.fromSeed(seedColor: kIndigoColor),
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.black,
  primaryColor: Colors.white,
  cardColor: Colors.black,
  hintColor: Colors.white.withValues(alpha: .7),
  focusColor: Colors.white.withValues(alpha: .7),

  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: Colors.white.withValues(alpha: .7)),
  brightness: Brightness.dark,
  tabBarTheme: TabBarThemeData(indicatorColor: Colors.white),
);
