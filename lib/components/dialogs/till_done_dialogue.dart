import 'package:flutter/material.dart';

/// Shows [content] in a dialog the user cannot dismiss, runs [action], then
/// closes the dialog.
Future<bool?> tillDoneDialogue(
  BuildContext context,
  Widget content,
  Future Function() action, // Ensuring that the action returns a Future
) async {
  // Resolved now, while [context] is mounted: the page that opened the
  // dialog may be closed before [action] finishes, and looking the navigator
  // up from an unmounted context is what crashed here.
  // Root navigator, as showDialog uses.
  final navigator = Navigator.of(context, rootNavigator: true);
  final dialogRoute = DialogRoute<bool>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        content: content,
      );
    },
  );
  navigator.push(dialogRoute);

  try {
    await action();
  } finally {
    // Close only our dialog, even if other routes were pushed meanwhile.
    if (dialogRoute.isActive) {
      navigator.removeRoute(dialogRoute);
    }
  }

  return true; // Optionally return a value indicating completion
}
