// import 'package:bsat/services/supabase_auth.dart';
import 'package:flutter/material.dart';
import 'package:bsat/components/hero.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/services.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

import '../../components/buildTextField.dart';

class OtpVerificationPage extends StatefulWidget {
  OtpVerificationPage();

  @override
  _OtpVerificationPageState createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final _formKey = GlobalKey<FormState>();
  String _otp = '';
  String number = '';
  int _otpLength = 6;
  bool isLoading = false;
  bool otpSent = false;

  // SupabaseAuth _supabaseAuth = SupabaseAuth(Supabase.instance.client);

  late List<FocusNode> _focusNodes;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _focusNodes = List.generate(_otpLength, (index) => FocusNode());
    _controllers =
        List.generate(_otpLength, (index) => TextEditingController());
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.length == 1 && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    if (_controllers.every((controller) => controller.text.isNotEmpty)) {
      _handleVerification(
          _controllers.map((controller) => controller.text).join());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: kPagePadding * 3),
              myHeroWidget(context),
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
      ),
    );
  }

  Widget _buildPhoneQuery() {
    return Column(
      children: [
        Text(
          'Enter number to receive OTP',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        SizedBox(height: kPagePadding),
        buildTextField(
          'Phone',
          (value) => number = value,
          keyboardType: TextInputType.number,
          isPhone: true,
        ),
        SizedBox(height: kPagePadding * 2),
        SizedBox(
          width: double.infinity,
          child: _buildOutlinedButton(
            () {
              setState(() {
                otpSent = true;
              });
            },
            Text("GET OTP"),
          ),
        ),
      ],
    );
  }

  Widget _buildOTPQuery() {
    return Column(
      children: [
        Text(
          'Enter OTP sent to $number',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        SizedBox(height: kPagePadding),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(
            _otpLength,
            (index) => SizedBox(
              width: 50,
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                decoration: InputDecoration(
                  counterText: "",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (value) => _onChanged(value, index),
              ),
            ),
          ),
        ),
        SizedBox(height: kPagePadding * 2),
        SizedBox(
          width: double.infinity,
          child: _buildOutlinedButton(
            () => _handleVerification(
                _controllers.map((controller) => controller.text).join()),
            Text("Verify OTP"),
          ),
        ),
        SizedBox(height: kPagePadding),
        TextButton(
          onPressed: _handleResendOtp,
          child: Text("Resend OTP"),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              otpSent = false;
            });
          },
          child: Text("Change number"),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    Function(String) onChanged, {
    bool isPassword = false,
    TextInputType? keyboardType,
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
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter $label';
        }
        if (value.length != 6) {
          return 'OTP must be 6 digits long';
        }
        return null;
      },
    );
  }

  Widget _buildOutlinedButton(Function onTap, Widget child) {
    return OutlinedButton(
      onPressed: () {
        onTap();
      },
      child: child,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius)),
        padding: EdgeInsets.symmetric(vertical: 15),
      ),
    );
  }

  void _handleVerification(String otp) async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        isLoading = true;
      });
      // AuthResponse authResponse = await _supabaseAuth.verifyPhoneOTP(
      //     phone: "+254${number.replaceFirst(RegExp(r'0'), '')}", token: otp);

      // if (authResponse.user == null) {}
      // TODO: Implement OTP verification logic here
      // print('Verifying OTP: $otp for phone number: ${widget.phoneNumber}');
      // After verification, you might want to navigate to the next screen
      // or show a success message
    }
  }

  void _handleResendOtp() {
    // TODO: Implement logic to resend OTP
    // print('Resending OTP to ${widget.phoneNumber}');
  }
}
