// Ported from the BSAT Local Lab prototype (lib/ui/scan_page.dart).
// Frames are decoded on the phone with zxing2; nothing is stored or sent.
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:bsat/services/lan/lan_pairing.dart';
import 'package:bsat/services/lan/lan_qr_decode.dart';

/// In-app camera scanner for pairing invitations. Pops with the scanned text
/// only after it passed [PairingInvitation.parseScanned]; any other QR code
/// is rejected on screen and scanning continues. Pops with null when the
/// user goes back to manual entry. Scanning establishes no trust: the caller
/// runs the normal authenticated pairing and code comparison.
class ScanInvitationPage extends StatefulWidget {
  const ScanInvitationPage({super.key});

  @override
  State<ScanInvitationPage> createState() => _ScanInvitationPageState();
}

enum _ScanState { starting, scanning, permissionDenied, unavailable, failed }

/// Minimum interval between decoded frames; the rest are skipped.
const Duration _decodeInterval = Duration(milliseconds: 250);

typedef _Frame = ({Uint8List luma, int width, int height, int stride});

String? _decodeFrame(_Frame frame) => decodeQrFromLuminance(
  frame.luma,
  width: frame.width,
  height: frame.height,
  rowStride: frame.stride,
);

class _ScanInvitationPageState extends State<ScanInvitationPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  _ScanState _state = _ScanState.starting;
  String? _failure;
  String? _rejected;
  bool _decoding = false;
  bool _done = false;
  DateTime _lastDecode = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera while in the background; reopen on return. Only
    // once scanning: the permission dialog also makes the app inactive.
    if (_state != _ScanState.scanning) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        !_done) {
      _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _state = _ScanState.starting;
      _failure = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setState(_ScanState.unavailable);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _camera = camera;
      await camera.initialize();
      if (!mounted || !identical(_camera, camera)) {
        await camera.dispose();
        return;
      }
      await camera.startImageStream(_onFrame);
      _setState(_ScanState.scanning);
    } on CameraException catch (error) {
      await _stopCamera();
      final code = error.code;
      if (code.contains('AccessDenied') || code.contains('AccessRestricted')) {
        _setState(_ScanState.permissionDenied);
      } else {
        _failure = code;
        _setState(_ScanState.failed);
      }
    } catch (error) {
      await _stopCamera();
      _failure = error.runtimeType.toString();
      _setState(_ScanState.unavailable);
    }
  }

  void _setState(_ScanState state) {
    if (mounted) setState(() => _state = state);
  }

  Future<void> _stopCamera() async {
    final camera = _camera;
    _camera = null;
    if (camera == null) return;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
    } catch (_) {}
    await camera.dispose();
  }

  void _onFrame(CameraImage image) {
    if (_decoding || _done || image.planes.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastDecode) < _decodeInterval) return;
    _lastDecode = now;
    final plane = image.planes.first; // luminance (Y)
    final _Frame frame = (
      // Copied: the camera reuses the buffer after this callback.
      luma: Uint8List.fromList(plane.bytes),
      width: image.width,
      height: image.height,
      stride: plane.bytesPerRow,
    );
    _decoding = true;
    compute(
      _decodeFrame,
      frame,
    ).then(_onDecoded, onError: (_) {}).whenComplete(() => _decoding = false);
  }

  void _onDecoded(String? text) {
    if (text == null || _done || !mounted) return;
    try {
      PairingInvitation.parseScanned(text);
    } on FormatException catch (error) {
      // The scanned content itself is never shown or logged.
      setState(() => _rejected = error.message);
      return;
    }
    _done = true;
    _stopCamera();
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing QR')),
      body: switch (_state) {
        _ScanState.starting => const _Centered(
          icon: Icons.photo_camera,
          text: 'Opening the camera…',
          busy: true,
        ),
        _ScanState.scanning => _scanner(context),
        _ScanState.permissionDenied => _Centered(
          icon: Icons.no_photography,
          text:
              'Camera permission denied. Allow camera access for BSAT '
              '(Android Settings → Apps → BSAT → '
              'Permissions), then try again — or enter the code manually.',
          actions: _retryActions(context),
        ),
        _ScanState.unavailable => _Centered(
          icon: Icons.videocam_off,
          text: 'No usable camera on this phone. Enter the code manually.',
          actions: _retryActions(context),
        ),
        _ScanState.failed => _Centered(
          icon: Icons.error_outline,
          text:
              'The camera could not be started ($_failure). Try again, '
              'or enter the code manually.',
          actions: _retryActions(context),
        ),
      },
    );
  }

  Widget _scanner(BuildContext context) {
    final camera = _camera;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (camera != null && camera.value.isInitialized)
                ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: camera.value.previewSize?.height ?? 1,
                      height: camera.value.previewSize?.width ?? 1,
                      child: CameraPreview(camera),
                    ),
                  ),
                ),
              Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _rejected ??
                    'Point the camera at the QR code on the other phone '
                        '(Paired Devices → LAN invite).',
                style: TextStyle(
                  color: _rejected == null
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Enter the code manually instead'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _retryActions(BuildContext context) => [
    FilledButton(onPressed: _start, child: const Text('Try again')),
    OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Enter the code manually'),
    ),
  ];
}

class _Centered extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool busy;
  final List<Widget> actions;

  const _Centered({
    required this.icon,
    required this.text,
    this.busy = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (busy) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
            const SizedBox(height: 16),
            for (final action in actions)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: action),
          ],
        ),
      ),
    );
  }
}
