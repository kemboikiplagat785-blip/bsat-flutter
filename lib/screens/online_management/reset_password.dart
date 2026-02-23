import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/header.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';

class ResetPasswordPage extends StatefulWidget {
  final String email;
  const ResetPasswordPage({super.key, required this.email});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  bool _obscurePassword = true;
  String error = '';
  String password = '';
  String confirmPassword = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          spacing: kPagePadding / 2,
          children: [
            // const MyHeroWidget(),
            header(context, 'Reset Password'),
            const SizedBox(height: kPagePadding * 3),
              if (error == '')
                Container()
              else
                Container(
                  padding: kPagePaddingInsets,
                  margin: const EdgeInsets.only(bottom: kPagePadding),
                  decoration: BoxDecoration(
                    color: kErrorColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(kBorderRadius),
                  ),
                  child: Column(
                    children: [
                      Text(
                        error,
                        style: TextStyle(color: kErrorColor),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: kPagePadding * 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: _buildTextField(
                'Password',
                (value) {
                  password = value;
                },
                isPassword: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: _buildTextField(
                'Confirm Password',
                (value) {
                  confirmPassword = value;
                },
                isPassword: true,
              ),
            ),
            const SizedBox(height: kPagePadding * 2),
            ElevatedButton(
              onPressed: () async {
                // Handle password reset logic
                final response = await AuthService().resetPassword(
                  newPassword: password,
                  email: widget.email, // Provide the email associated with the account
                );

                if (response['success']) {
                  // Navigate to login or home page after successful reset
                  await showSuccessDialog(context, text: "Password reset successful. Log in to continue");
                  // Navigator.of(context).popUntil((route) => route.isFirst);
                  Navigator.pop(context);
                } else {
                  setState(() {
                    error = response['message'] ?? 'Password reset failed';
                  });
                }
              },
              child: Text('Reset Password'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    Function(String) onChanged, {
    bool isPassword = false,
    bool isEmail = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      obscureText: isPassword ? _obscurePassword : false,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword
                      ? CupertinoIcons.eye_slash
                      : CupertinoIcons.eye,
                  // color: kDullColor,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              )
            : null,
      ),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter $label';
        }
        if (isEmail) {
          // Basic email validation
          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
            return 'Please enter a valid email address';
          }
        }
        return null;
      },
    );
  }

  
}
