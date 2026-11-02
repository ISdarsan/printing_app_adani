import 'dart:io';

import 'package:canteen_adani/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadInterFont);
  String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

  testWidgets('the Coming soon popup names the feature and closes with OK', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showComingSoonDialog(context, feature: 'SMS Broadcast Specials'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.textContaining('SMS Broadcast Specials is not available yet'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('the popup does not overflow on a small phone with large text', (t) async {
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 480), textScaler: TextScaler.linear(1.6)),
      child: MaterialApp(
        builder: (c, child) => Center(child: SizedBox(width: 320, height: 480, child: child)),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showComingSoonDialog(context, feature: 'SMS Broadcast Specials'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  test('the cashier menu shows Coming soon and can no longer reach the SMS broadcast code', () {
    final s = read('lib/billing_dashboard_page.dart');
    expect(s, contains("showComingSoonDialog(context, feature: 'SMS Broadcast Specials')"));
    expect(s.contains('showSMSBroadcastDialog'), isFalse);
    expect(s.contains('sms_broadcast_helper'), isFalse);
  });

  test('the admin menu is unchanged (still opens the existing SMS dialog)', () {
    expect(read('lib/admin_dashboard_page.dart'), contains('showSMSBroadcastDialog(context)'));
  });
}
