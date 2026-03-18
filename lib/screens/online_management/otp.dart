// import 'package:bsat/services/supabase_auth.dart';
import 'package:bsat/components/header.dart';
import 'package:flutter/material.dart';
import 'package:bsat/components/hero.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter_otp_text_field/flutter_otp_text_field.dart';

// import 'package:supabase_flutter/supabase_flutter.dart';

import '../../components/buildTextField.dart';
import '../../services/auth_service.dart';

class OtpVerificationPage extends StatefulWidget {
  const OtpVerificationPage({super.key});

  @override
  _OtpVerificationPageState createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final _formKey = GlobalKey<FormState>();
  String _otpCode = '';
  String email = '';
  bool isLoading = false;
  bool otpSent = false;
  String error = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // const MyHeroWidget(),
            header(context, 'OTP Verification'),
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
            Container(
              decoration: BoxDecoration(
                // color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      otpSent ? _buildOTPQuery() : _buildPhoneQuery(),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: kPagePadding * 2),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneQuery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter email',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        SizedBox(height: kPagePadding),
        buildTextField(
          'Email',
          (value) => email = value,
          keyboardType: TextInputType.emailAddress,
          isPhone: true,
        ),
        SizedBox(height: kPagePadding * 2),
        SizedBox(
          width: double.infinity,
          child: _buildOutlinedButton(
            () async {
              setState(() {
                error = '';
                isLoading = true;
              });
              final result = await AuthService().requestOTP(email: email);

              if (result['success']) {
                setState(() {
                  otpSent = true;
                  error = '';
                  isLoading = false;
                });
              } else {
                // ScaffoldMessenger.of(context).showSnackBar(
                //   SnackBar(content: Text(result['message'])),
                // );
                setState(() {
                  error = result['message'];
                  isLoading = false;
                });
              }
            },
            isLoading ? CircularProgressIndicator() : Text("GET OTP"),
          ),
        ),
      ],
    );
  }

  Widget _buildOTPQuery() {
    return Column(
      children: [
        Text(
          'Enter OTP sent to $email',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        SizedBox(height: kPagePadding),
        OtpTextField(
          numberOfFields: 5,
          borderColor: kPrimaryColor,
          focusedBorderColor: kPrimaryColor,
          enabledBorderColor: kGrayColor,
          borderWidth: 2,
          showFieldAsBox: true,
          fieldWidth: 50,
          borderRadius: BorderRadius.circular(kBorderRadius),
          onCodeChanged: (String code) {
            _otpCode = code;
            setState(() {
              error = '';
            });
          },
          onSubmit: (String verificationCode) {
            _otpCode = verificationCode;
            _handleVerification(verificationCode);
          },
        ),
        SizedBox(height: kPagePadding * 2),
        SizedBox(
          width: double.infinity,
          child: _buildOutlinedButton(
            () {
              _handleVerification(_otpCode);
            },
            isLoading ? CircularProgressIndicator() : Text("Verify OTP"),
          ),
        ),
        SizedBox(height: kPagePadding),
        TextButton(
          onPressed: () {
            AuthService().requestOTP(email: email);
            setState(() {
              otpSent = true;
            });
          },
          child: Text("Resend OTP"),
        ),
        TextButton(
          onPressed: () {
            otpSent = false;
            error = '';
            setState(() {});
          },
          child: Text("Change email"),
        ),
      ],
    );
  }

  Widget _buildOutlinedButton(Function onTap, Widget child) {
    return OutlinedButton(
      onPressed: () {
        onTap();
      },
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius)),
        padding: EdgeInsets.symmetric(vertical: 15),
      ),
      child: child,
    );
  }

  void _handleVerification(String otp) async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        isLoading = true;
        error = '';
      });

      //print('Verifying OTP: $otp for email: $email');

      final result = await AuthService().verifyOTP(email: email, otp: otp);

      if (result['success']) {
        // OTP verified successfully
        Navigator.of(context).pop({'verified': true, 'email': email});
      } else {
        // OTP verification failed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'])),
        );
        setState(() {
          error = result['message'];
          isLoading = false;
        });
      }

      setState(() {
        isLoading = false;
      });
    }
  }
}
