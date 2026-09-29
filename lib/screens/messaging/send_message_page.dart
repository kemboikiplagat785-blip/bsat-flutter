import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/backend_service.dart';

class SendMessagePage extends StatefulWidget {
  const SendMessagePage({super.key});

  @override
  State<SendMessagePage> createState() => _SendMessagePageState();
}

class _SendMessagePageState extends State<SendMessagePage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final bool _isLoading = false;

  void _handleSend() async {
    final BackendService backendService = BackendService();

    final result = await backendService.sendMessage(
        title: "Hello", body: "World", topic: "general");

    debugPrint("Send Message Result: $result");
    // if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text("Please enter both title and message")),
    //   );
    //   return;
    // }

    // setState(() => _isLoading = true);

    // try {
    //   // For local testing, we connect to a backend server running on our machine
    //   // This is because the FCM HTTP v1 API requires server-side authentication.
    //   // 1. Run the server: `cd server && npm install && node index.js`
    //   // 2. Connect device via USB and run `adb reverse tcp:3000 tcp:3000` (for Android)
    //   //    This maps the device's localhost:3000 to your PC's localhost:3000

    //   // Use `http://10.0.2.2:3000/send` for Android Emulator
    //   // Use `http://localhost:3000/send` for iOS Simulator
    //   // Use `http://192.168.x.x:3000/send` for real device over Wi-Fi

    //   // We'll assume successful ADB reverse mapping for real Android devices
    //   const String serverUrl = 'http://api.bsat.co.ke/api/fcm/send';

    //   final response = await http.post(
    //     Uri.parse(serverUrl),
    //     headers: <String, String>{
    //       'Content-Type': 'application/json',
    //     },
    //     body: jsonEncode(
    //       <String, dynamic>{
    //         'title': _titleController.text,
    //         'body': _bodyController.text,
    //         'topic': 'general',
    //       },
    //     ),
    //   );

    //   debugPrint("Server Response: ${response.statusCode} - ${response.body}");

    //   setState(() => _isLoading = false);

    //   if (mounted) {
    //     if (response.statusCode == 200) {
    //       showCupertinoDialog(
    //         context: context,
    //         builder: (ctx) => CupertinoAlertDialog(
    //           title: const Text("Message Sent"),
    //           content: const Text(
    //               "Your message has been queued successfully via the backend."),
    //           actions: [
    //             CupertinoDialogAction(
    //               child: const Text("OK"),
    //               onPressed: () {
    //                 Navigator.of(ctx).pop();
    //                 Navigator.of(context).pop();
    //               },
    //             ),
    //           ],
    //         ),
    //       );
    //     } else {
    //       // Fallback message if server is unreachable
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         SnackBar(
    //           content: Text(
    //               "Failed to send: ${response.statusCode}. Is the server running?"),
    //           action: SnackBarAction(
    //             label: "Retry",
    //             onPressed: _handleSend,
    //           ),
    //         ),
    //       );
    //     }
    //   }
    // } catch (e) {
    //   setState(() => _isLoading = false);
    //   debugPrint("Error sending request to backend: $e");
    //   if (mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       SnackBar(
    //         content: Text("Error connecting to server: $e\nEnsure 'adb reverse tcp:3000 tcp:3000' is run."),
    //         duration: const Duration(seconds: 5),
    //       ),
    //     );
    //   }
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        title: const Text("Send Message",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Title Input
            _buildInputGroup(
                'Title', 'Enter notification title', _titleController),
            const SizedBox(height: 24),

            // Body Input using multiline
            _buildInputGroup(
                'Message', 'Type your message here...', _bodyController,
                maxLines: 5),
            const SizedBox(height: 32),

            // Send Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: kPrimaryColor.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                        "Send Message",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputGroup(
      String label, String hint, TextEditingController controller,
      {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }
}
