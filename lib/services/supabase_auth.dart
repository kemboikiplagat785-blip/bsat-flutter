// import 'package:supabase_flutter/supabase_flutter.dart';

// class SupabaseAuth {
//   final SupabaseClient _supabase;

//   SupabaseAuth(this._supabase);

//   // Email signup
//   Future<AuthResponse> signUpWithEmail({
//     required String email,
//     required String password,
//   }) async {
//     return await _supabase.auth.signUp(
//       email: email,
//       password: password,
//     );
//   }

//   // Email signin
//   Future<AuthResponse> signInWithEmail({
//     required String email,
//     required String password,
//   }) async {
//     return await _supabase.auth.signInWithPassword(
//       email: email,
//       password: password,
//     );
//   }

//   // Phone signup - Step 1: Send OTP
//   Future<AuthResponse> signUpWithPhone({
//     required String phone,
//     required String password,
//   }) async {
//     return await _supabase.auth.signUp(
//       phone: phone,
//       password: password,
//     );
//   }

//   // Phone signup - Step 2: Verify OTP
//   Future<AuthResponse> verifyPhoneOTP({
//     required String phone,
//     required String token,
//   }) async {
//     return await _supabase.auth.verifyOTP(
//       type: OtpType.sms,
//       token: token,
//       phone: phone,
//     );
//   }

//   // Phone signin
//   Future<AuthResponse> signInWithPhone({
//     required String phone,
//     required String password,
//   }) async {
//     return await _supabase.auth.signInWithPassword(
//       phone: phone,
//       password: password,
//     );
//   }

//   // Password reset request (for email)
//   Future<void> resetPassword({required String email}) async {
//     await _supabase.auth.resetPasswordForEmail(email);
//   }

//   // Sign out (local)
//   Future<void> signOut() async {
//     await _supabase.auth.signOut(scope: SignOutScope.local);
//   }

//   // Sign out (others)
//   Future<void> signOthersOut() async {
//     await _supabase.auth.signOut(scope: SignOutScope.others);
//   }

//   // Get current user
//   User? get currentUser => _supabase.auth.currentUser;

//   // Check if user is signed in
//   bool get isSignedIn => _supabase.auth.currentUser != null;
// }
