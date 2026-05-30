import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp({super.key});

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  bool _ready = false;

  Future<void> _init() async {
    await initializeDateFormatting('pt_BR', null);

    // ✅ tempo mínimo para splash "parecer banco"
    await Future.delayed(const Duration(milliseconds: 2400));
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _ready
          ? const AppWidget()
          : const _FynoBankSplash(), // splash premium
    );
  }
}

/// Splash premium "estilo banco"
class _FynoBankSplash extends StatefulWidget {
  const _FynoBankSplash({super.key});

  @override
  State<_FynoBankSplash> createState() => _FynoBankSplashState();
}

class _FynoBankSplashState extends State<_FynoBankSplash>
    with SingleTickerProviderStateMixin {
  static const String _bgImage = 'assets/images/fyno_header.png';
  static const String _logoIcon = 'assets/icon/fyno_icon.png';

  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _logoScale = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ garante que não “pisque” e carrega antes
    precacheImage(const AssetImage(_bgImage), context);
    precacheImage(const AssetImage(_logoIcon), context);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const fynoGreen = Color(0xFF00E5A8);

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeIn,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ✅ imagem em tela inteira (cover)
            Image.asset(
              _bgImage,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF0E0E11)),
            ),

            // ✅ blur leve + overlay escuro (cara de banco)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0E0E11).withOpacity(0.78),
                      const Color(0xFF0E0E11).withOpacity(0.88),
                      const Color(0xFF061812).withOpacity(0.92),
                    ],
                  ),
                ),
              ),
            ),

            // ✅ glow sutil (sem ficar “travando”)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.0, -0.15),
                      radius: 0.9,
                      colors: [fynoGreen.withOpacity(0.14), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),

            // Conteúdo central (logo + slogan + loader)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Logo do app (fixo, só um micro “scale” de entrada)
                    ScaleTransition(
                      scale: _logoScale,
                      child: Column(
                        children: [
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              color: Colors.white.withOpacity(0.06),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.10),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: fynoGreen.withOpacity(0.20),
                                  blurRadius: 26,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Image.asset(
                                _logoIcon,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.account_balance_wallet_rounded,
                                  color: fynoGreen,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'FYNO',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.4,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'clareza total sobre seu dinheiro',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.2,
                              color: Colors.white.withOpacity(0.70),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Loader discreto, contínuo (estilo banco)
                    Column(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              fynoGreen,
                            ),
                            backgroundColor: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Carregando…',
                          style: TextStyle(
                            fontSize: 12.8,
                            color: Colors.white.withOpacity(0.55),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
