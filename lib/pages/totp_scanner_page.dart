import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../totp/totp_service.dart';

class TotpScannerPage extends StatefulWidget {
  const TotpScannerPage({super.key});

  @override
  State<TotpScannerPage> createState() => _TotpScannerPageState();
}

class _TotpScannerPageState extends State<TotpScannerPage>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  StreamSubscription<BarcodeCapture>? _barcodeSubscription;
  String? _invalidValue;
  bool _returning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
      returnImage: false,
      autoZoom: true,
    );
    _barcodeSubscription = _controller.barcodes.listen(_handleCapture);
    unawaited(_startScanner());
  }

  Future<void> _startScanner() async {
    try {
      await _controller.start();
    } on MobileScannerException {
      // The scanner widget renders startup and permission errors.
    }
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_returning) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      try {
        TotpConfig.fromUri(value);
      } on FormatException {
        if (value != _invalidValue && mounted) {
          setState(() => _invalidValue = value);
        }
        continue;
      }
      _returning = true;
      unawaited(_controller.stop());
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_startScanner());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_barcodeSubscription?.cancel());
    _barcodeSubscription = null;
    super.dispose();
    unawaited(_controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描 TOTP 二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final windowSize = math.min(constraints.maxWidth - 48, 280.0);
          final scanWindow = Rect.fromCenter(
            center: constraints.biggest.center(Offset.zero),
            width: windowSize,
            height: windowSize,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                scanWindow: scanWindow,
                scanWindowUpdateThreshold: 8,
                tapToFocus: true,
                errorBuilder: _buildScannerError,
              ),
              IgnorePointer(
                child: ScanWindowOverlay(
                  controller: _controller,
                  scanWindow: scanWindow,
                  borderRadius: BorderRadius.circular(8),
                  borderWidth: 3,
                  color: const Color(0x99000000),
                ),
              ),
              if (_invalidValue != null)
                const Positioned(
                  left: 24,
                  right: 24,
                  bottom: 104,
                  child: Text(
                    '这不是有效的 TOTP 二维码',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _TorchButton(controller: _controller),
                      const SizedBox(width: 24),
                      _CameraButton(controller: _controller),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScannerError(
    BuildContext context,
    MobileScannerException error,
  ) {
    final permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            permissionDenied ? '需要相机权限才能扫描二维码\n请在系统设置中允许相机权限' : '相机启动失败，请返回后重试',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final enabled =
            state.isInitialized &&
            state.isRunning &&
            state.torchState != TorchState.unavailable;
        return IconButton.filledTonal(
          tooltip: state.torchState == TorchState.on ? '关闭闪光灯' : '打开闪光灯',
          onPressed: enabled ? controller.toggleTorch : null,
          icon: Icon(
            state.torchState == TorchState.on
                ? Icons.flash_on
                : Icons.flash_off,
          ),
        );
      },
    );
  }
}

class _CameraButton extends StatelessWidget {
  const _CameraButton({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final enabled =
            state.isInitialized &&
            state.isRunning &&
            (state.availableCameras == null || state.availableCameras! > 1);
        return IconButton.filledTonal(
          tooltip: '切换摄像头',
          onPressed: enabled ? controller.switchCamera : null,
          icon: const Icon(Icons.cameraswitch_outlined),
        );
      },
    );
  }
}
