import 'dart:io';

import 'package:canteen_adani/discard_bill_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fonts.dart';

/// Regression tests for the full-analysis sweep: crashes that only appear with
/// unusual stored data, a lost-bill accident, and the wrong-phone-date guard.
void main() {
  setUpAll(loadInterFont);
  String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

  group('source guards (each confirmed to fail on the code before the sweep)', () {
    test('stored date keys are parsed with tryParse, never DateTime.parse, in the charts', () {
      for (final f in ['lib/admin_dashboard_page.dart', 'lib/admin_analytics_page.dart']) {
        final s = read(f);
        expect(RegExp(r'DateTime\.parse\((docs\[|weeklyDocs\[)').hasMatch(s), isFalse, reason: f);
      }
      expect(read('lib/admin_dashboard_page.dart'), contains('DateTime.tryParse(date) == null'));
    });

    test("an expense without an amount or time can never crash a list or its detail page", () {
      final hard = RegExp(r"\['amount'\] as num");
      for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        expect(hard.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test("the bill counter is read as a number, not a hard `as int` (a decimal would block every bill)", () {
      final s = read('lib/print_bill_page.dart');
      expect(s.contains("['lastNumber'] as int"), isFalse);
      expect(s, contains("['lastNumber'] ?? 0) as num).toInt()"));
    });

    test('every writer that files money under the phone date checks the phone clock first', () {
      for (final f in [
        'lib/print_bill_page.dart',
        'lib/credit_detail_page.dart',
        'lib/cash_reconciliation_page.dart',
      ]) {
        final s = read(f);
        expect(s, contains('ClockGuard.confirmSafe(context)'), reason: f);
        expect(s, contains('ClockGuard.warmUp()'), reason: f);
      }
    });

    test('the billing screen guards Back with a discard confirmation and blocks leaving while saving', () {
      final s = read('lib/print_bill_page.dart');
      expect(s, contains('PopScope('));
      expect(s, contains('canPop: _billItems.isEmpty && !_isSaving && !_saveFlowActive'));
      expect(s, contains('confirmDiscardBill('));
    });
  });

  test('every named route that a screen navigates to is registered in main.dart (a typo would crash at runtime)', () {
    final main = read('lib/main.dart');
    final defined = RegExp(r"'(/[a-z_]*)'\s*:").allMatches(main).map((m) => m.group(1)!).toSet();
    expect(defined.length, greaterThan(15), reason: 'route table not parsed');
    final used = <String, String>{}; // route -> file
    final calls = RegExp(r"(?:pushNamed|pushReplacementNamed|pushNamedAndRemoveUntil|popAndPushNamed|_nav)\s*\([^;]*?'(/[a-z_]+)'", dotAll: true);
    final fields = RegExp(r"route:\s*'(/[a-z_]+)'");
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in [...calls.allMatches(src), ...fields.allMatches(src)]) {
        used[m.group(1)!] = f.path;
      }
    }
    expect(used.length, greaterThan(10), reason: 'navigation calls not found');
    used.forEach((route, file) {
      expect(defined.contains(route), isTrue, reason: '$file navigates to $route, which is not registered');
    });
  });

  group('discard-bill dialog', () {
    Widget host(void Function(BuildContext) go) => MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: MaterialApp(
            builder: (c, child) => Center(child: SizedBox(width: 360, height: 640, child: child)),
            home: Builder(builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(onPressed: () => go(context), child: const Text('open')),
                ),
              );
            }),
          ),
        );

    testWidgets('says how many items and the amount, and defaults to keeping the bill', (t) async {
      bool? result;
      await t.pumpWidget(host((c) => confirmDiscardBill(c, itemCount: 3, total: 125.5).then((v) => result = v)));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
      expect(find.textContaining('3 items'), findsOneWidget);
      expect(find.textContaining('₹125.50'), findsOneWidget);
      // tapping outside the dialog (barrier) keeps the bill
      // a point inside the 360 px app box but outside the dialog
      await t.tapAt(t.getTopLeft(find.byType(Scaffold).first) + const Offset(4, 4));
      await t.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('Keep editing returns false, Discard bill returns true', (t) async {
      bool? result;
      await t.pumpWidget(host((c) => confirmDiscardBill(c, itemCount: 1, total: 10).then((v) => result = v)));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.textContaining('1 item '), findsOneWidget); // singular
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(result, isFalse);

      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.text('Discard bill'));
      await t.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('does not overflow on a small phone with large text', (t) async {
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(320, 480), textScaler: TextScaler.linear(1.6)),
        child: MaterialApp(
          builder: (c, child) => Center(child: SizedBox(width: 320, height: 480, child: child)),
          home: Builder(builder: (context) => Scaffold(
                body: Center(child: ElevatedButton(
                  onPressed: () => confirmDiscardBill(context, itemCount: 12, total: 123456.75),
                  child: const Text('open'))))),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
