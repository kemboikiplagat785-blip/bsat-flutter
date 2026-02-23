import 'package:bsat/components/dialogs/ask_device_name_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/screens/online_management/otp.dart';
// import 'package:bsat/services/supabase_auth.dart';
import 'package:bsat/utils/constants.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

import '../../components/hero.dart';
import 'package:bsat/screens/online_management/register_device.dart';
import 'package:bsat/services/auth_service.dart';
import '../online_management/login.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  String email = '';
  String name = '';
  String password = '';
  String confirmPassword = '';
  String error = '';
  String linkUrl = '';
  bool showPassword = false;

  // final _supabaseAuth = SupabaseAuth(Supabase.instance.client);
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: kPagePadding * 3),
            const MyHeroWidget(),
            const SizedBox(height: kPagePadding * 2),
            Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Text(
                          'Sign Up',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: kPagePadding),
                        if (error == '')
                          Container()
                        else
                          Column(
                            children: [
                              Container(
                                padding: kPagePaddingInsets,
                                decoration: BoxDecoration(
                                  color: kErrorColor.withAlpha(20),
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                ),
                                child: Text(
                                  error,
                                  style: TextStyle(color: kErrorColor),
                                ),
                              ),
                              const SizedBox(height: kPagePadding),
                            ],
                          ),
                        const SizedBox(height: kPagePadding),
                        _buildTextField(
                          'Email',
                          (value) => email = value,
                          keyboardType: TextInputType.emailAddress,
                          isEmail: true,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: kPagePadding),
                        _buildTextField(
                          'Name',
                          (value) => name = value,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: kPagePadding),
                        Container(
                          padding: const EdgeInsets.only(
                            left: kPagePadding,
                          ),
                          decoration: BoxDecoration(
                            color: kGrayColor.withAlpha(30),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(kBorderRadius),
                              bottomLeft: Radius.circular(kBorderRadius),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Text('bingwa.bsat.co.ke/'),
                              Expanded(
                                child: _buildTextField(
                                  'Link url',
                                  (value) => linkUrl = value,
                                  autofillHints: const [AutofillHints.username],
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: kPagePadding),
                        _buildTextField(
                          'Password',
                          (value) => password = value,
                          isPassword: true,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: kPagePadding),
                        _buildTextField(
                          'Confirm Password',
                          (value) => confirmPassword = value,
                          isPassword: true,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                        ),
                        const SizedBox(height: kPagePadding * 2),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: kPagePaddingInsets,
                              elevation: 0,
                              backgroundColor: kPrimaryColorLight,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                              ),
                            ),
                            onPressed: _handleSignup,
                            child: const Text(
                              'SIGN UP',
                              style: TextStyle(
                                color: kPrimaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: kPagePadding),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pushReplacement(
                                  PageRouteBuilder(
                                    pageBuilder: (context, animation,
                                            secondaryAnimation) =>
                                        const LoginPage(),
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
    List<String>? autofillHints,
    TextInputAction? textInputAction,
  }) {
    return TextFormField(
      obscureText: isPassword && !showPassword,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  showPassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                  // color: kDullColor,
                ),
                onPressed: () {
                  setState(() {
                    showPassword = !showPassword;
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

  void _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        isLoading = true;
      });
      showLoadingDialog(context, text: "Creating your account");
      try {
        final result = await AuthService().signup(
          email: email,
          password: password,
          name: name,
          linkExtension: linkUrl,
        );
        // Offer saving credentials to Google / platform autofill providers.
        TextInput.finishAutofillContext(shouldSave: true);
        Navigator.of(context).pop(); // Close loading dialog
        if (result['success']) {
          //print('Signup successful');

          Navigator.of(context).pushReplacement(
            CupertinoPageRoute(
              builder: (context) => RegisterDevicePage(),
            ),
          );
        } else {
          print('Signup failed: ${result}');
          setState(() {
            error = result['message'] ?? 'Signup failed';
          });
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
