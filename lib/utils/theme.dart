import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'package:google_fonts/google_fonts.dart';

var lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: kIndigoColor),
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: kBgColor,
  cardColor: kLightColor.withOpacity(.5),
  hintColor: kSecondaryColor,
  focusColor: kSecondaryColor,
  indicatorColor: kIndigoColor,
  textTheme: GoogleFonts.karlaTextTheme().apply(bodyColor: kIndigoColor),
  // brightness: Brightness.dark
);

var darkTheme = ThemeData(
  // colorScheme: ColorScheme.fromSeed(seedColor: kIndigoColor),
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: kSecondaryColor,
  primaryColor: kLightColor,
  indicatorColor: kLightColor,
  cardColor: kLightColor.withOpacity(.1),
  hintColor: kLightColor.withOpacity(.7),
  focusColor: kLightColor.withOpacity(.7),

  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withOpacity(.7)),
  brightness: Brightness.dark,
);

var brownTheme = ThemeData(
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: kBrownBackground,
  primaryColor: kLightColor,
  indicatorColor: kLightColor,
  cardColor: kLightColor.withOpacity(.1),
  hintColor: kLightColor.withOpacity(.7),
  focusColor: kLightColor.withOpacity(.7),
  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withOpacity(.7)),
  brightness: Brightness.dark,
);

var indigoTheme = ThemeData(
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: kIndigoColor.withAlpha(150),
  primaryColor: kLightColor,
  indicatorColor: kLightColor,
  cardColor: kLightColor.withOpacity(.1),
  hintColor: kLightColor.withOpacity(.7),
  focusColor: kLightColor.withOpacity(.7),
  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withOpacity(.7)),
  brightness: Brightness.dark,
);

var darkPurpleTheme = ThemeData(
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: Color(0xFF190b28),
  primaryColor: kLightColor,
  indicatorColor: kLightColor,
  cardColor: kLightColor.withOpacity(.1),
  hintColor: kLightColor.withOpacity(.7),
  focusColor: kLightColor.withOpacity(.7),
  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withOpacity(.7)),
  brightness: Brightness.dark,
);

var pinkTheme = ThemeData(
  // colorScheme: ColorScheme.fromSeed(seedColor: kIndigoColor),
  fontFamily: GoogleFonts.karla().fontFamily,
  useMaterial3: true,
  scaffoldBackgroundColor: Color.fromARGB(255, 82, 23, 52),
  primaryColor: kLightColor,
  indicatorColor: kLightColor,
  cardColor: kLightColor.withOpacity(.1),
  hintColor: kLightColor.withOpacity(.7),
  focusColor: kLightColor.withOpacity(.7),

  textTheme: GoogleFonts.karlaTextTheme()
      .apply(bodyColor: kLightColor.withOpacity(.7)),
  brightness: Brightness.dark,
);
