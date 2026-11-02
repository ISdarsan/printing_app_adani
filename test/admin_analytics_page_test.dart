import 'dart:async';

import 'package:canteen_adani/admin_analytics_page.dart';
import 'package:canteen_adani/analytics_calc.dart';
import 'package:canteen_adani/analytics_loader.dart';
import 'package:canteen_adani/business_time.dart';
import 'package:canteen_adani/canteen_provider.dart';
import 'package:canteen_adani/canteen_selector.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fonts.dart';

/// Renders the real Analytics page (all five tabs and their charts) with
/// realistic data produced by the app's own calculation code, no Firebase.

AnalyticsResult fakeResult({int bills = 60, int days = 220, bool empty = false}) {
  final now = DateTime.now();
  final agg = BillAggregates(now);
  final daily = DailyTotals();
  if (!empty) {
    const items = ['Tea', 'Coffee', 'Masala Dosa', 'Idli Sambar', 'Veg Biryani', 'Samosa'];
    const modes = ['Cash', 'UPI', 'Credit'];
    for (var i = 0; i < bills; i++) {
      final when = now.subtract(Duration(hours: i * 9 + 1));
      agg.add({
        'timestamp': Timestamp.fromDate(when),
        'totalAmount': 40.0 + (i % 7) * 25,
        'paymentMode': modes[i % 3],
        'createdByEmail': i.isEven ? 'asha@x.com' : 'ravi@x.com',
        'items': [
          {'name': items[i % items.length], 'quantity': 1 + i % 3, 'price': 20.0 + i % 5, 'costPrice': 8.0},
          // an item whose cost is unknown must not break the profit tab
          {'name': items[(i + 2) % items.length], 'quantity': 1, 'price': 30.0},
        ],
      });
    }
    for (var d = 0; d < days; d++) {
      final day = now.subtract(Duration(days: d));
      final key = BusinessTime.dateKey(day);
      daily.add({
        'date': key,
        'canteenId': 'main',
        'totalSales': 1500.0 + (d % 9) * 120,
        'totalCash': 700.0 + (d % 4) * 50,
        'totalUpi': 500.0 + (d % 5) * 40,
        'totalCredit': 300.0 + (d % 3) * 30,
      }, 'main_$key', CanteenProvider.dateFromDailyStatsDocumentId);
    }
  }
  final monthly = daily.monthlySales();
  return AnalyticsResult(
    range: AnalyticsRange.months6,
    loadedAt: now,
    itemPerformance: agg.itemPerformance(),
    staffPerformance: agg.staffPerformance(),
    timeSlots: agg.timeSlots(),
    anomalies: daily.anomalies(),
    forecast: agg.forecast(),
    weekly: daily.weekly(BusinessTime.dateKeyDaysAgo(now, 7)),
    monthlySales: monthly,
    last6MonthKeys: lastSixMonthKeys(monthly, <String>{}),
    billsRead: bills,
    billsUsed: agg.billCount,
    dailyStatsRead: empty ? 0 : days,
    expensesRead: 0,
    truncated: false,
  );
}

// replayable for every listener (the page may rebuild its top bar)
Stream<List<CanteenChoice>> choices() => Stream.multi((ctrl) => ctrl.add(buildCanteenChoices([
      const MapEntry('north', {'name': 'North Canteen'}),
      const MapEntry('south', {'name': 'South Canteen'}),
    ])));

Widget host(AnalyticsLoadFn load,
        {Size size = const Size(360, 800), double scale = 1}) =>
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        builder: (c, w) => Center(child: SizedBox(width: size.width, height: size.height, child: w)),
        home: AdminAnalyticsPage(loadAnalytics: load, canteenChoices: choices()),
      ),
    );

const tabs = ['Weekly', 'Monthly', 'Payments', 'Profit', 'Ops'];

Future<void> visitEveryTab(WidgetTester t) async {
  for (final name in tabs) {
    await t.tap(find.text(name));
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull, reason: 'tab $name threw');
  }
}

void main() {
  setUpAll(loadInterFont);

  testWidgets('loads and every tab renders its charts without an exception (phone, 360 wide)', (t) async {
    await t.pumpWidget(host((r, c, {isCancelled, onProgress}) async => fakeResult()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Analytics Insights'), findsOneWidget);
    expect(find.textContaining('60 bills'), findsOneWidget);
    for (final n in tabs) {
      expect(find.text(n), findsOneWidget);
    }
    expect(t.takeException(), isNull);
    await visitEveryTab(t);
  });

  for (final c in [
    (name: 'small phone 320 wide', size: const Size(320, 568), scale: 1.0),
    (name: 'phone, 160% text', size: const Size(360, 800), scale: 1.6),
  ]) {
    testWidgets('no overflow or exception on every tab: ${c.name}', (t) async {
      await t.pumpWidget(host((r, canteen, {isCancelled, onProgress}) async => fakeResult(),
          size: c.size, scale: c.scale));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await visitEveryTab(t);
    });
  }

  testWidgets('a canteen with no data at all shows "no data" placeholders, not an exception', (t) async {
    await t.pumpWidget(host((r, c, {isCancelled, onProgress}) async => fakeResult(empty: true)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('0 bills'), findsOneWidget);
    expect(t.takeException(), isNull);
    await visitEveryTab(t);
  });

  testWidgets('a failed load shows a plain-language error and Retry loads again', (t) async {
    var calls = 0;
    await t.pumpWidget(host((r, c, {isCancelled, onProgress}) async {
      calls++;
      if (calls == 1) throw StateError('network down');
      return fakeResult();
    }));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Could not load analytics'), findsOneWidget);
    expect(find.textContaining('network down'), findsNothing, reason: 'no raw exception text');
    await t.tap(find.text('Retry'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(calls, 2);
    expect(find.textContaining('60 bills'), findsOneWidget);
  });

  testWidgets('starts on ALL canteens and asks the loader for the canteen the admin picks', (t) async {
    final asked = <String>[];
    await t.pumpWidget(host((r, canteen, {isCancelled, onProgress}) async {
      asked.add(canteen);
      return fakeResult(bills: canteen == 'north' ? 12 : 60);
    }));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(asked, ['all']);
    expect(find.text('All canteens'), findsOneWidget);

    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('North Canteen').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(asked, ['all', 'north']);
    expect(find.textContaining('12 bills'), findsOneWidget);
    expect(find.textContaining('60 bills'), findsNothing);
  });

  testWidgets('a slow answer for an OLD choice never overwrites the newer choice', (t) async {
    final slowAll = Completer<AnalyticsResult>();
    await t.pumpWidget(host((r, canteen, {isCancelled, onProgress}) {
      if (canteen == 'all') return slowAll.future; // still loading when the admin switches
      return Future.value(fakeResult(bills: 12));
    }));
    await t.pump();
    // switch to North while "all" is still loading (a spinner is running, so
    // pumpAndSettle would never settle: pump fixed durations instead)
    await t.tap(find.byType(DropdownButton<String>));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('North Canteen').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('12 bills'), findsOneWidget);
    // now the old "all" request finally answers
    slowAll.complete(fakeResult(bills: 60));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('12 bills'), findsOneWidget, reason: 'late old result must be ignored');
    expect(find.textContaining('60 bills'), findsNothing);
  });
}
