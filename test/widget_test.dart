import 'package:controle_financeiro/app/theme/app_theme.dart';
import 'package:controle_financeiro/app/theme/theme_controller.dart';
import 'package:controle_financeiro/shared/widgets/adaptive_pair.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget responsiveHost({required double width, required double textScale}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const AdaptivePair(
                first: SizedBox(key: Key('first'), height: 50),
                second: SizedBox(key: Key('second'), height: 50),
              ),
            ),
          ),
        ),
      ),
    );
  }

  test('themes expose distinct accessible light and dark palettes', () {
    final light = AppTheme.lightTheme;
    final dark = AppTheme.darkTheme;

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.surface, isNot(dark.colorScheme.surface));
    expect(light.colorScheme.onSurface, isNot(dark.colorScheme.onSurface));
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
  });

  test('theme choice is saved and restored', () async {
    SharedPreferences.setMockInitialValues({});
    await ThemeController.instance.load();

    await ThemeController.instance.setMode(ThemeMode.dark);
    final preferences = await SharedPreferences.getInstance();

    expect(ThemeController.instance.mode, ThemeMode.dark);
    expect(preferences.getString('app_theme_mode'), 'dark');
  });

  testWidgets('adaptive pair stays side by side when there is room', (
    tester,
  ) async {
    await tester.pumpWidget(responsiveHost(width: 700, textScale: 1));

    final first = tester.getTopLeft(find.byKey(const Key('first')));
    final second = tester.getTopLeft(find.byKey(const Key('second')));

    expect(first.dy, second.dy);
    expect(second.dx, greaterThan(first.dx));
  });

  testWidgets('adaptive pair stacks on narrow screens', (tester) async {
    await tester.pumpWidget(responsiveHost(width: 320, textScale: 1));

    final first = tester.getTopLeft(find.byKey(const Key('first')));
    final second = tester.getTopLeft(find.byKey(const Key('second')));

    expect(second.dy, greaterThan(first.dy));
  });

  testWidgets('adaptive pair stacks when accessibility text is enlarged', (
    tester,
  ) async {
    await tester.pumpWidget(responsiveHost(width: 700, textScale: 1.4));

    final first = tester.getTopLeft(find.byKey(const Key('first')));
    final second = tester.getTopLeft(find.byKey(const Key('second')));

    expect(second.dy, greaterThan(first.dy));
  });
}
