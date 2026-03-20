import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MyWebsitePage extends StatefulWidget {
  // Replace with your actual website URL
  final String websiteUrl = "https://portal.bsat.co.ke";

  const MyWebsitePage({Key? key}) : super(key: key);

  @override
  State<MyWebsitePage> createState() => _MyWebsitePageState();
}

class _MyWebsitePageState extends State<MyWebsitePage> {
  late final WebViewController _controller;
  int _loadingProgress = 0;

  @override
  void initState() {
    super.initState();

    // Initialize the WebViewController
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // Allow JavaScript
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _loadingProgress = progress;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _loadingProgress = 0;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _loadingProgress = 100;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
              Page resource error:
              code: ${error.errorCode}
              description: ${error.description}
              errorType: ${error.errorType}
              isForMainFrame: ${error.isForMainFrame}
            ''');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.websiteUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // This allows the user to use the phone's back button to navigate 
      // backward in the website's history instead of instantly closing the app page
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("My Portal"),
          actions:[
            // Add a reload button to the AppBar
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _controller.reload();
              },
            ),
          ],
        ),
        body: Stack(
          children:[
            // The actual WebView
            WebViewWidget(controller: _controller),
            
            // A loading progress bar at the top of the screen
            if (_loadingProgress < 100)
              LinearProgressIndicator(
                value: _loadingProgress / 100.0,
                backgroundColor: Colors.transparent,
                color: Colors.blue,
              ),
          ],
        ),
      ),
    );
  }
}