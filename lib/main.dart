import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app/app.dart';
import 'app/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  bool _ready = false;

  Future<void> _init() async {
    await Future.wait([
      initializeDateFormatting('pt_BR', null),
      ThemeController.instance.load(),
      // Tempo mínimo curto para a transição de marca não piscar em aparelhos rápidos.
      Future<void>.delayed(const Duration(milliseconds: 350)),
    ]);
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _init();

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    // Quando o app estiver pronto, o AppWidget passa a ser o único MaterialApp.
    // Manter outro MaterialApp por fora criava dois Navigators e fazia o botão
    // físico Voltar, em alguns fluxos, minimizar o aplicativo antes da hora.
    if (_ready) return const AppWidget();
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _FynoBrandSplash(),
    );
  }
}

class _FynoBrandSplash extends StatefulWidget {
  const _FynoBrandSplash();

  @override
  State<_FynoBrandSplash> createState() => _FynoBrandSplashState();
}

class _FynoBrandSplashState extends State<_FynoBrandSplash>
    with SingleTickerProviderStateMixin {
  static const _lightBackground = 'assets/brand/fyno_splash_light.jpg';
  static const _darkBackground = 'assets/brand/fyno_splash_dark.jpg';
  static const _lightMark = 'assets/brand/fyno_mark.png';
  static const _darkMark = 'assets/brand/fyno_mark_on_dark.png';

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = curve;
    _scale = Tween<double>(begin: .92, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: const Offset(0, .08),
      end: Offset.zero,
    ).animate(curve);
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(_lightBackground), context);
    precacheImage(const AssetImage(_darkBackground), context);
    precacheImage(const AssetImage(_lightMark), context);
    precacheImage(const AssetImage(_darkMark), context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ThemeController.instance.mode;
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final dark =
        mode == ThemeMode.dark || (mode == ThemeMode.system && platformDark);
    final foreground = dark ? const Color(0xFFF1F8F5) : const Color(0xFF10231C);
    final muted = foreground.withValues(alpha: .68);
    final accent = dark ? const Color(0xFF86E8C4) : const Color(0xFF0B765B);

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF07140F) : const Color(0xFFF7FAF8),
      body: FadeTransition(
        opacity: _fade,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              dark ? _darkBackground : _lightBackground,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, _, _) => ColoredBox(
                color: dark ? const Color(0xFF07140F) : const Color(0xFFF7FAF8),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? [
                          const Color(0xFF07140F).withValues(alpha: .08),
                          const Color(0xFF07140F).withValues(alpha: .18),
                          const Color(0xFF07140F).withValues(alpha: .30),
                        ]
                      : [
                          Colors.white.withValues(alpha: .10),
                          Colors.white.withValues(alpha: .04),
                          const Color(0xFFE8F4EF).withValues(alpha: .16),
                        ],
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 620;
                  final markSize = compact ? 112.0 : 144.0;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
                    child: Column(
                      children: [
                        const Spacer(flex: 3),
                        SlideTransition(
                          position: _slide,
                          child: ScaleTransition(
                            scale: _scale,
                            child: Semantics(
                              label: 'Fyno',
                              image: true,
                              child: Column(
                                children: [
                                  Image.asset(
                                    dark ? _darkMark : _lightMark,
                                    width: markSize,
                                    height: markSize,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.auto_graph_rounded,
                                      color: accent,
                                      size: markSize * .55,
                                    ),
                                  ),
                                  SizedBox(height: compact ? 6 : 10),
                                  Text(
                                    'Fyno',
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: compact ? 36 : 42,
                                      height: 1,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Seu dinheiro, com clareza.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: compact ? 14 : 16,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: .1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  minHeight: 3,
                                  color: accent,
                                  backgroundColor: foreground.withValues(
                                    alpha: .12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Preparando seu espaço',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: .2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 16),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
