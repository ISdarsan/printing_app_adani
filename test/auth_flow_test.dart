import 'dart:async';

import 'package:canteen_adani/canteen_provider.dart';
import 'package:canteen_adani/login_page.dart';
import 'package:canteen_adani/role_routing.dart';
import 'package:canteen_adani/role_splash_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RouteLog extends NavigatorObserver {
  final names = <String?>[];
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      names.add(newRoute?.settings.name);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      names.add(route.settings.name);
}

Widget app(Widget home, RouteLog log) => MaterialApp(
      navigatorObservers: [log],
      home: home,
      routes: {
        '/admin_dashboard': (_) => const Scaffold(body: Text('ADMIN DASH')),
        '/billing_dashboard': (_) => const Scaffold(body: Text('CASHIER DASH')),
        '/login': (_) => const Scaffold(body: Text('LOGIN')),
      },
    );

StaffRecord staff(Map<String, dynamic> d) => (exists: true, data: d);

void main() {
  group('decideRole (authorization decision)', () {
    test('active admin -> admin dashboard', () {
      final d = decideRole(docExists: true, data: {'role': 'admin'});
      expect(d.outcome, RoleOutcome.admin);
      expect(d.route, '/admin_dashboard');
      expect(d.allowed, isTrue);
    });
    test('active cashier -> billing dashboard', () {
      final d = decideRole(docExists: true, data: {'role': 'cashier', 'active': true});
      expect(d.route, '/billing_dashboard');
    });
    test('missing active flag counts as active (same as firestore.rules)', () {
      expect(decideRole(docExists: true, data: {'role': 'cashier'}).allowed, isTrue);
    });
    test('active == false is denied for BOTH roles', () {
      for (final r in ['admin', 'cashier']) {
        final d = decideRole(docExists: true, data: {'role': r, 'active': false});
        expect(d.outcome, RoleOutcome.deactivated);
        expect(d.route, isNull);
      }
    });
    test('no staff document -> denied', () {
      final d = decideRole(docExists: false);
      expect(d.outcome, RoleOutcome.notFound);
      expect(d.allowed, isFalse);
    });
    test('unknown, empty or missing role -> denied (never defaults to cashier)', () {
      for (final data in [
        {'role': 'owner'},
        {'role': ''},
        <String, dynamic>{},
      ]) {
        expect(decideRole(docExists: true, data: data).allowed, isFalse, reason: '$data');
      }
    });
    test('a read error is a denial, not a fallback', () {
      final d = decideRole(docExists: false, error: StateError('offline'));
      expect(d.outcome, RoleOutcome.error);
      expect(d.allowed, isFalse);
      expect(d.title, 'Connection Error');
    });
    test('only an allowed user skips the hold; denials hold long enough to read', () {
      expect(decideRole(docExists: false).denialHold.inMilliseconds, greaterThanOrEqualTo(2000));
    });
  });

  group('RoleSplashPage: no fixed delay, authorization never skipped', () {
    testWidgets('admin is on the dashboard right after the lookup completes (no 3 s wait)', (t) async {
      final log = RouteLog();
      final gate = Completer<StaffRecord>();
      await t.pumpWidget(app(
        RoleSplashPage(role: 'u1', loadStaff: (_) => gate.future, signOut: () async {}),
        log,
      ));
      await t.pump(const Duration(milliseconds: 50));
      // while the lookup is outstanding: spinner, still on the splash
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('ADMIN DASH'), findsNothing);

      gate.complete(staff({'role': 'admin'}));
      await t.pump(); // lookup finished
      await t.pump(const Duration(milliseconds: 400)); // route transition only
      expect(find.text('ADMIN DASH'), findsOneWidget);
      // far below the old 3 000 ms
    });

    testWidgets('cashier lands on the billing dashboard with their own branch set', (t) async {
      CanteenProvider.applyStaffData({'role': 'admin'}); // stale state from a previous user
      final log = RouteLog();
      await t.pumpWidget(app(
        RoleSplashPage(
          role: 'u2',
          loadStaff: (_) async => staff({'role': 'cashier', 'canteenId': 'north', 'canteenName': 'North'}),
          signOut: () async {},
        ),
        log,
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('CASHIER DASH'), findsOneWidget);
      expect(CanteenProvider.isAdmin, isFalse);
      expect(CanteenProvider.selectedCanteenId, 'north');
    });

    testWidgets('deactivated staff never reach a dashboard and are signed out', (t) async {
      final log = RouteLog();
      var signOuts = 0;
      await t.pumpWidget(app(
        RoleSplashPage(
          role: 'u3',
          loadStaff: (_) async => staff({'role': 'admin', 'active': false}),
          signOut: () async => signOuts++,
        ),
        log,
      ));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('This account has been deactivated.'), findsOneWidget);
      expect(find.text('ADMIN DASH'), findsNothing);
      expect(signOuts, 0, reason: 'message is held before sign-out');
      await t.pump(const Duration(seconds: 2));
      await t.pump(const Duration(milliseconds: 400));
      expect(signOuts, 1);
      expect(find.text('LOGIN'), findsOneWidget);
      expect(log.names.contains('/admin_dashboard'), isFalse);
      expect(log.names.contains('/billing_dashboard'), isFalse);
    });

    testWidgets('missing staff document -> denied and signed out', (t) async {
      var signOuts = 0;
      await t.pumpWidget(app(
        RoleSplashPage(
          role: 'u4',
          loadStaff: (_) async => (exists: false, data: null),
          signOut: () async => signOuts++,
        ),
        RouteLog(),
      ));
      await t.pump();
      expect(find.text('User role not found.'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(milliseconds: 400));
      expect(signOuts, 1);
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('lookup failure shows a connection error, signs out, never opens a dashboard', (t) async {
      final log = RouteLog();
      var signOuts = 0;
      await t.pumpWidget(app(
        RoleSplashPage(
          role: 'u5',
          loadStaff: (_) async => throw StateError('network down'),
          signOut: () async => signOuts++,
        ),
        log,
      ));
      await t.pump();
      expect(find.text('Connection Error'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(milliseconds: 400));
      expect(signOuts, 1);
      expect(find.text('LOGIN'), findsOneWidget);
      expect(find.textContaining('DASH'), findsNothing);
    });

    testWidgets('unknown role is denied', (t) async {
      await t.pumpWidget(app(
        RoleSplashPage(
          role: 'u6',
          loadStaff: (_) async => staff({'role': 'visitor'}),
          signOut: () async {},
        ),
        RouteLog(),
      ));
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('DASH'), findsNothing);
      expect(find.text('LOGIN'), findsOneWidget);
    });
  });

  group('LoginPage: loading behaviour', () {
    Finder signInButton() => find.text('Sign In');

    testWidgets('a second tap while signing in is ignored; spinner shown; goes to next page', (t) async {
      final gate = Completer<String?>();
      var calls = 0;
      await t.pumpWidget(MaterialApp(
        home: LoginPage(
          signIn: (e, p) {
            calls++;
            return gate.future;
          },
          nextPage: (uid) => Scaffold(body: Text('NEXT $uid')),
        ),
      ));
      await t.pump(const Duration(seconds: 1));
      await t.enterText(find.byType(TextField).first, 'a@b.com');
      await t.enterText(find.byType(TextField).last, 'secret');
      final buttonCenter = t.getCenter(signInButton());
      await t.tap(signInButton());
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(signInButton(), findsNothing, reason: 'label is replaced by the spinner');
      await t.tapAt(buttonCenter); // second tap at the same spot
      await t.pump();
      await t.tapAt(buttonCenter); // and a third
      await t.pump();
      expect(calls, 1, reason: 'duplicate tap must not start a second sign-in');

      gate.complete('uid-9');
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('NEXT uid-9'), findsOneWidget);
    });

    testWidgets('wrong password shows the error and re-enables the button', (t) async {
      await t.pumpWidget(MaterialApp(
        home: LoginPage(
          signIn: (e, p) async => throw FirebaseAuthException(code: 'wrong-password'),
          nextPage: (uid) => const Scaffold(body: Text('NEXT')),
        ),
      ));
      await t.pump(const Duration(seconds: 1));
      await t.enterText(find.byType(TextField).first, 'a@b.com');
      await t.enterText(find.byType(TextField).last, 'bad');
      await t.tap(signInButton());
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Invalid email or password. Try again.'), findsOneWidget);
      expect(find.text('NEXT'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('an unexpected error shows a generic message and no navigation', (t) async {
      await t.pumpWidget(MaterialApp(
        home: LoginPage(
          signIn: (e, p) async => throw StateError('boom'),
          nextPage: (uid) => const Scaffold(body: Text('NEXT')),
        ),
      ));
      await t.pump(const Duration(seconds: 1));
      await t.enterText(find.byType(TextField).first, 'a@b.com');
      await t.enterText(find.byType(TextField).last, 'x');
      await t.tap(signInButton());
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('An error occurred. Please try again.'), findsOneWidget);
      expect(find.text('NEXT'), findsNothing);
    });

    testWidgets('signing in alone opens the role check, not a dashboard', (t) async {
      // The default next page is RoleSplashPage; here we only assert the
      // injected hook receives the uid and that no dashboard route is pushed.
      final log = RouteLog();
      await t.pumpWidget(MaterialApp(
        navigatorObservers: [log],
        home: LoginPage(
          signIn: (e, p) async => 'u-1',
          nextPage: (uid) => Scaffold(body: Text('ROLE CHECK $uid')),
        ),
      ));
      await t.pump(const Duration(seconds: 1));
      await t.enterText(find.byType(TextField).first, 'a@b.com');
      await t.enterText(find.byType(TextField).last, 'x');
      await t.tap(signInButton());
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('ROLE CHECK u-1'), findsOneWidget);
      expect(log.names.where((n) => n?.contains('dashboard') ?? false), isEmpty);
    });
  });
}
