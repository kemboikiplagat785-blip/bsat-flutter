import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/screens/onboarding/otp.dart';
// import 'package:bsat/services/supabase_auth.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

import '../../components/hero.dart';
import 'login.dart';

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  String email = '';
  String password = '';
  String confirmPassword = '';
  String error = '';

  // final _supabaseAuth = SupabaseAuth(Supabase.instance.client);
  bool isLoading = false;

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
                decoration: const BoxDecoration(
                  // color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        error == ''
                            ? Container()
                            : Row(
                                children: [
                                  Text(
                                    error,
                                    style: TextStyle(color: kErrorColor),
                                  ),
                                  const SizedBox(height: kPagePadding),
                                ],
                              ),
                        Text(
                          'Sign Up',
                          // style: Theme.of(context).textTheme.headline6,
                        ),
                        const SizedBox(height: kPagePadding),
                        _buildTextField(
                          'Email',
                          (value) => email = value,
                          keyboardType: TextInputType.emailAddress,
                          isEmail: true,
                        ),
                        const SizedBox(height: kPagePadding),
                        _buildTextField(
                          'Password',
                          (value) => password = value,
                          isPassword: true,
                        ),
                        const SizedBox(height: kPagePadding),
                        _buildTextField(
                          'Confirm Password',
                          (value) => confirmPassword = value,
                          isPassword: true,
                        ),
                        const SizedBox(height: kPagePadding * 2),
                        SizedBox(
                          width: double.infinity,
                          child: _buildOutlinedButton(
                            () => _handleSignup(),
                            const Text("SIGN UP"),
                            outlineColor: kPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: kPagePadding),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () {
                                // Navigator.of(context).pop();
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    pageBuilder: (context, animation,
                                            secondaryAnimation) =>
                                        LoginPage(),
                                    transitionsBuilder: (context, animation,
                                        secondaryAnimation, child) {
                                      return CupertinoPageTransition(
                                        primaryRouteAnimation: animation,
                                        secondaryRouteAnimation:
                                            secondaryAnimation,
                                        linearTransition: true,
                                        child: child,
                                      );
                                    },
                                  ),
                                );
                              },
                              child: const Text("Back to Login"),
                            ),
                          ],
                        ),
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

  Widget _buildTextField(
    String label,
    Function(String) onChanged, {
    bool isPassword = false,
    bool isEmail = false,
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
        if (isEmail) {
          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
            return 'Please enter a valid email address';
          }
        }
        if (isPassword && label == 'Confirm Password') {
          if (value != password) {
            return 'Passwords do not match';
          }
        }
        return null;
      },
    );
  }

  Widget _buildOutlinedButton(
    Function onTap,
    Widget child, {
    Color? fgColor,
    Color? outlineColor,
  }) {
    return OutlinedButton(
      onPressed: () {
        onTap();
      },
      child: child,
      style: OutlinedButton.styleFrom(
        foregroundColor: fgColor,
        backgroundColor: outlineColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius)),
        padding: kPagePaddingInsets / 2,
      ),
    );
  }

  void _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        isLoading = true;
      });
      showLoadingDialog(context, text: "Creating your account");
      try {
        // await _supabaseAuth
        //     .signUpWithEmail(
        //   password: password,
        //   email: email,
        // )
        //     .then((response) {
        //   Navigator.of(context).pop();
        //   if (response.user != null) {
        //     Navigator.of(context).push(
        //       PageRouteBuilder(
        //         pageBuilder: (context, animation, secondaryAnimation) =>
        //             OtpVerificationPage(),
        //         transitionsBuilder:
        //             (context, animation, secondaryAnimation, child) {
        //           return CupertinoPageTransition(
        //             primaryRouteAnimation: animation,
        //             secondaryRouteAnimation: secondaryAnimation,
        //             linearTransition: true,
        //             child: child,
        //           );
        //         },
        //       ),
        //     );
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       const SnackBar(
        //         content: Text('Account created successfully!'),
        //       ),
        //     );
        //   }
        // });
      } catch (error) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${error.toString()}')),
        );
      }
    }
  }
}
