import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'receipt_item_draft.dart';
import 'receipt_qr_service.dart';

/// Abre o portal oficial quando ele exige validação humana (por exemplo,
/// reCAPTCHA). Depois da validação, o HTML já autorizado é processado somente
/// no aparelho e os itens são devolvidos para o fluxo da transação.
class ReceiptQrPortalPage extends StatefulWidget {
  const ReceiptQrPortalPage({required this.uri, super.key});

  final Uri uri;

  @override
  State<ReceiptQrPortalPage> createState() => _ReceiptQrPortalPageState();
}

class _ReceiptQrPortalPageState extends State<ReceiptQrPortalPage> {
  late final WebViewController _controller;
  Timer? _probeTimer;
  bool _extracting = false;
  bool _completed = false;
  int _progress = 0;
  String _status =
      'Se o portal pedir, marque “Não sou um robô”. O Fyno importa os produtos automaticamente.';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_configureAndLoad());

    // Alguns portais trocam o conteúdo por AJAX depois do reCAPTCHA e não
    // disparam uma nova navegação. A sondagem lê apenas o HTML da página atual.
    _probeTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _tryExtract(silent: true),
    );
  }

  Future<void> _configureAndLoad() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(Colors.white);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageFinished: (_) => unawaited(_tryExtract(silent: true)),
        onWebResourceError: (error) {
          if (error.isForMainFrame != false && mounted && !_completed) {
            setState(() {
              _status =
                  'O portal demorou para responder. Tente recarregar a página.';
            });
          }
        },
      ),
    );

    // O reCAPTCHA usa recursos e cookies do Google em outro domínio.
    // WebViews Android bloqueiam cookies de terceiros por padrão.
    if (_controller.platform is AndroidWebViewController) {
      final cookieManager = AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      );
      await cookieManager.setAcceptThirdPartyCookies(
        _controller.platform as AndroidWebViewController,
        true,
      );
    }
    await _controller.loadRequest(widget.uri);
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    super.dispose();
  }

  Future<void> _tryExtract({required bool silent}) async {
    if (_extracting || _completed) return;
    _extracting = true;
    try {
      final value = await _controller.runJavaScriptReturningResult(
        'document.documentElement ? document.documentElement.outerHTML : ""',
      );
      final htmlText = _decodeJavaScriptString(value);
      final items = ReceiptQrService.parsePortalHtml(htmlText);
      if (items.isNotEmpty) {
        _completed = true;
        _probeTimer?.cancel();
        if (!mounted) return;
        setState(() => _status = '${items.length} produto(s) encontrado(s).');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (mounted) Navigator.of(context).pop<List<ReceiptItemDraft>>(items);
        return;
      }

      if (!silent && mounted) {
        setState(() {
          _status =
              'Ainda não encontrei os produtos. Conclua a validação e aguarde a nota aparecer.';
        });
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(
          () => _status = 'Não consegui ler esta página. Tente recarregar.',
        );
      }
    } finally {
      _extracting = false;
    }
  }

  String _decodeJavaScriptString(Object value) {
    final raw = '$value';
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is String) return decoded;
      } catch (_) {}
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Validar cupom no portal'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          SafeArea(
            top: false,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_status, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _extracting
                            ? null
                            : () => _tryExtract(silent: false),
                        icon: _extracting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_done_rounded),
                        label: const Text('Importar produtos desta nota'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
