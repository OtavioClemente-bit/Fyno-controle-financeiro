import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'receipt_qr_service.dart';

class ReceiptQrScannerPage extends StatefulWidget {
  const ReceiptQrScannerPage({super.key});

  @override
  State<ReceiptQrScannerPage> createState() => _ReceiptQrScannerPageState();
}

class _ReceiptQrScannerPageState extends State<ReceiptQrScannerPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _imagePicker = ImagePicker();
  final _controller = MobileScannerController(
    // NFC-e usa QR denso. A resolução padrão do plugin é apenas 640x480 no
    // Android, insuficiente em muitos comprovantes impressos.
    cameraResolution: const Size(1920, 1080),
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 300,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
    autoZoom: true,
  );

  late final AnimationController _lineAnimation;
  bool _handlingResult = false;
  bool _analyzingImage = false;
  String _status = 'Posicione o QR Code da NFC-e dentro da moldura';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lineAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_handlingResult && !_analyzingImage) {
          unawaited(_controller.start());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lineAnimation.dispose();
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.replaceAll('\n', '').trim();
      if (raw == null || raw.isEmpty) continue;
      if (await _acceptRawValue(raw)) return;
    }
  }

  Future<bool> _acceptRawValue(String raw) async {
    if (_handlingResult) return false;
    if (!ReceiptQrService.isWebQrValue(raw)) {
      HapticFeedback.lightImpact();
      if (mounted) {
        setState(() {
          _status = 'Esse QR Code não contém um endereço válido de cupom';
        });
      }
      return false;
    }

    _handlingResult = true;
    await _controller.stop();
    await HapticFeedback.mediumImpact();
    if (!mounted) return false;
    setState(() => _status = 'QR Code identificado');
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return false;
    Navigator.of(context).pop(raw);
    return true;
  }

  Future<void> _pickFromGallery() async {
    if (_handlingResult || _analyzingImage) return;
    setState(() {
      _analyzingImage = true;
      _status = 'Procurando QR Code na imagem…';
    });
    await _controller.stop();

    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final capture = await _controller.analyzeImage(image.path);
      final barcode = capture?.barcodes.firstOrNull;
      final raw = barcode?.rawValue?.replaceAll('\n', '').trim();
      if (raw == null || raw.isEmpty) {
        if (mounted) {
          setState(() => _status = 'Nenhum QR Code encontrado nessa imagem');
        }
        return;
      }
      await _acceptRawValue(raw);
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Não foi possível analisar essa imagem');
      }
    } finally {
      _analyzingImage = false;
      if (mounted && !_handlingResult) {
        setState(() {});
        unawaited(_controller.start());
      }
    }
  }

  Future<void> _pasteReceiptLink() async {
    if (_handlingResult) return;
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final controller = TextEditingController(text: clipboard?.text?.trim());
    if (!mounted) return;
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.link_rounded),
        title: const Text('Colar link da NFC-e'),
        content: TextField(
          controller: controller,
          autofocus: controller.text.isEmpty,
          keyboardType: TextInputType.url,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'https://…/nfce/qrcode?p=…',
            helperText: 'Use somente o endereço exibido pelo QR Code da nota.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Consultar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    await _acceptRawValue(raw.trim());
  }

  Widget _cameraError(BuildContext context, MobileScannerException error) {
    final permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: const Color(0xFF071712),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                permissionDenied
                    ? Icons.no_photography_rounded
                    : Icons.camera_alt_outlined,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                permissionDenied
                    ? 'A câmera está desativada'
                    : 'Não foi possível iniciar a câmera',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                permissionDenied
                    ? 'Libere a câmera nas configurações para ler o QR Code.'
                    : 'Você ainda pode escolher uma imagem da galeria.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              if (permissionDenied)
                FilledButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Abrir configurações'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 48).clamp(240.0, 360.0);
            final scanWindow = Rect.fromCenter(
              center: Offset(
                constraints.maxWidth / 2,
                constraints.maxHeight * .43,
              ),
              width: width,
              height: width * .72,
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  // A moldura continua guiando o usuário, mas a imagem inteira
                  // é analisada para não cortar QR Codes grandes ou desalinhados.
                  fit: BoxFit.cover,
                  onDetect: _handleCapture,
                  errorBuilder: _cameraError,
                ),
                AnimatedBuilder(
                  animation: _lineAnimation,
                  builder: (context, _) => CustomPaint(
                    painter: _ScannerOverlayPainter(
                      scanWindow: scanWindow,
                      progress: _lineAnimation.value,
                      success: _handlingResult,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 8,
                  child: Row(
                    children: [
                      _RoundCameraButton(
                        tooltip: 'Fechar',
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      ValueListenableBuilder<MobileScannerState>(
                        valueListenable: _controller,
                        builder: (context, state, _) {
                          final torchOn = state.torchState == TorchState.on;
                          final available =
                              state.isRunning &&
                              state.torchState != TorchState.unavailable;
                          return _RoundCameraButton(
                            tooltip: torchOn ? 'Apagar flash' : 'Acender flash',
                            icon: torchOn
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            onPressed: available
                                ? () => _controller.toggleTorch()
                                : null,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xE6121F1B),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _handlingResult
                                  ? Icons.check_circle_rounded
                                  : Icons.qr_code_scanner_rounded,
                              color: _handlingResult
                                  ? const Color(0xFF55E7A8)
                                  : Colors.white,
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                'Leitura automática',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _analyzingImage
                                ? null
                                : _pickFromGallery,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                            ),
                            icon: _analyzingImage
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.photo_library_outlined),
                            label: const Text('Escolher imagem da galeria'),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _analyzingImage ? null : _pasteReceiptLink,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          icon: const Icon(Icons.content_paste_rounded),
                          label: const Text('Colar link do cupom'),
                        ),
                        const Text(
                          'A câmera apenas identifica o código; nenhuma foto é salva.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RoundCameraButton extends StatelessWidget {
  const _RoundCameraButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: const Color(0xA6000000),
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0x66000000),
      disabledForegroundColor: Colors.white38,
    ),
    icon: Icon(icon),
  );
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({
    required this.scanWindow,
    required this.progress,
    required this.success,
  });

  final Rect scanWindow;
  final double progress;
  final bool success;

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(
      scanWindow,
      const Radius.circular(24),
    );
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(rounded);
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, hole),
      Paint()..color = Colors.black.withValues(alpha: .54),
    );

    final accent = success ? const Color(0xFF55E7A8) : Colors.white;
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = accent.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final cornerPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const corner = 32.0;
    final left = scanWindow.left;
    final right = scanWindow.right;
    final top = scanWindow.top;
    final bottom = scanWindow.bottom;
    final corners = <Path>[
      Path()
        ..moveTo(left, top + corner)
        ..lineTo(left, top + 14)
        ..quadraticBezierTo(left, top, left + 14, top)
        ..lineTo(left + corner, top),
      Path()
        ..moveTo(right - corner, top)
        ..lineTo(right - 14, top)
        ..quadraticBezierTo(right, top, right, top + 14)
        ..lineTo(right, top + corner),
      Path()
        ..moveTo(left, bottom - corner)
        ..lineTo(left, bottom - 14)
        ..quadraticBezierTo(left, bottom, left + 14, bottom)
        ..lineTo(left + corner, bottom),
      Path()
        ..moveTo(right - corner, bottom)
        ..lineTo(right - 14, bottom)
        ..quadraticBezierTo(right, bottom, right, bottom - 14)
        ..lineTo(right, bottom - corner),
    ];
    for (final path in corners) {
      canvas.drawPath(path, cornerPaint);
    }

    if (!success) {
      final y =
          scanWindow.top +
          22 +
          ((scanWindow.height - 44) * progress.clamp(0.0, 1.0));
      final gradient = LinearGradient(
        colors: [
          const Color(0xFF31D49B).withValues(alpha: 0),
          const Color(0xFF31D49B),
          const Color(0xFF31D49B).withValues(alpha: 0),
        ],
      );
      canvas.drawLine(
        Offset(scanWindow.left + 22, y),
        Offset(scanWindow.right - 22, y),
        Paint()
          ..shader = gradient.createShader(
            Rect.fromLTRB(
              scanWindow.left + 22,
              y - 1,
              scanWindow.right - 22,
              y + 1,
            ),
          )
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.success != success;
}
