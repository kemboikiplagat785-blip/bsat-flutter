import 'package:flutter/material.dart';

import '../utils/constants.dart';

Widget buildTextField(
  String label,
  Function(String) onChanged, {
  bool isPassword = false,
  bool isPhone = false,
  TextInputType? keyboardType,
  bool dontValidate = false,
}) {
  return TextFormField(
    obscureText: isPassword,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kBorderRadius),
      ),
    ),
    onChanged: (value) {
      onChanged(value);
      // if (value == null || value.isEmpty) {
      //   FormFieldValidator().;
      // }
    },
    validator: (value) {
      if(dontValidate) return null;
      if (value == null || value.isEmpty) {
        return 'Please enter $label';
      }
      if (isPhone) {
        if (value.length != 10) {
          return 'Phone number invalid';
        }
      }
      return null;
    },
  );
}
