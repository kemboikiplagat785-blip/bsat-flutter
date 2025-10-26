import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/hero.dart';
import 'package:bsat/screens/dashboard.dart';
import './otp.dart';
import 'package:bsat/screens/online_management/reset_password.dart';
import './signup.dart';
import 'package:bsat/screens/online_management/online_management.dart';
// import 'package:bsat/services/supabase_auth.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/dialogs/ask_device_name_dialog.dart';
import '../../services/auth_service.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  String email = '';
  String password = '';
  bool _obscurePassword = true; // Add this

  String error = '';

  // final _supabaseAuth = SupabaseAuth(Supabase.instance.client);

  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: kPagePadding * 3),
            Container(
              // height: 150,
              child: myHeroWidget(context),
            ),
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
                      Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        // style: Theme.of(context).textTheme.headline6,
                      ),
                      const SizedBox(height: kPagePadding),
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
                      const SizedBox(height: kPagePadding * 2),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: kPagePaddingInsets,
                            backgroundColor: kPrimaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                          ),
                          onPressed: () {
                            _handleLogin();
                          },
                          child: Text(
                            'LOGIN',
                            style: TextStyle(
                              color: kIndigoColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: kPagePadding),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildOutlinedButton(
                            () {
                              Navigator.of(context).pushReplacement(
                                PageRouteBuilder(
                                  pageBuilder: (
                                    context,
                                    animation,
                                    secondaryAnimation,
                                  ) =>
                                      SignupPage(),
                                  transitionsBuilder: (
                                    context,
                                    animation,
                                    secondaryAnimation,
                                    child,
                                  ) {
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
                            const Text("Create account"),
                          ),
                          _buildOutlinedButton(
                            () async {
                              Map result = await Navigator.of(context).push(
                                PageRouteBuilder(
                                  pageBuilder: (context, animation,
                                          secondaryAnimation) =>
                                      OtpVerificationPage(),
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

                              if (result['verified'] == true) {
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    pageBuilder: (context, animation,
                                            secondaryAnimation) =>
                                        ResetPasswordPage(
                                            email: result['email']),
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
                              }
                            },
                            const Text("Forgot Password"),
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
      style: OutlinedButton.styleFrom(
        foregroundColor: fgColor,
        backgroundColor: outlineColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius)),
        padding: kPagePaddingInsets / 2,
      ),
      child: child,
    );
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        isLoading = true;
      });
      showLoadingDialog(context, text: "Signing you in");
      try {
        final result =
            await AuthService().login(email: email, password: password);

        Navigator.of(context).pop(); // Close loading dialog

        if (result['success']) {
          showLoadingDialog(context);
          if ((await AuthService().isDeviceRegisteredToMe())['success']) {
            Navigator.of(context).pop(); // Close loading dialog
            Navigator.of(context).pushReplacement(
              CupertinoPageRoute(
                builder: (context) => OnlineManagementScreen(),
              ),
            );
            return;
          }
          String deviceName =
              await showAskDeviceNameDialog(context, 'My 5th Device') ?? "";
          await AuthService().registerDeviceInfo(name: deviceName);
          Navigator.of(context).pop(); // Close loading dialog
          Navigator.of(context).pushReplacement(
            CupertinoPageRoute(
              builder: (context) => OnlineManagementScreen(),
            ),
          );
        } else {
          setState(() {
            error = result['message'] ?? 'Login failed';
            isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      } catch (error) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${error.toString()}')),
        );
      }
    }
  }
}
