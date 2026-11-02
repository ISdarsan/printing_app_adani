import 'package:canteen_adani/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests for the sign-in screen's interaction details. The sign-in call
// is injected, so no Firebase is needed. (Authentication behaviour itself is
// covered in auth_flow_test.dart and is unchanged.)
Widget host(LoginPage page,
        {Size size = const Size(360, 640), double scale = 1}) =>
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: MaterialApp(home: page),
    );

Future<void> settle(WidgetTester t) => t.pump(const Duration(seconds: 1));

void main() {
  testWidgets('empty fields: friendly message, no sign-in attempt', (t) async {
    var calls = 0;
    await t.pumpWidget(host(LoginPage(signIn: (e, p) async {
      calls++;
      return 'uid';
    })));
    await settle(t);
    await t.tap(find.text('Sign In'));
    await t.pump();
    expect(find.text('Please enter your email and password.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('only the email filled: still asks for the password', (t) async {
    var calls = 0;
    await t.pumpWidget(host(LoginPage(signIn: (e, p) async {
      calls++;
      return 'uid';
    })));
    await settle(t);
    await t.enterText(find.byType(TextField).first, 'a@b.com');
    await t.tap(find.text('Sign In'));
    await t.pump();
    expect(find.text('Please enter your email and password.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('pressing Done on the keyboard signs in (no need to reach the button)',
      (t) async {
    String? gotEmail, gotPassword;
    await t.pumpWidget(host(LoginPage(
      signIn: (e, p) async {
        gotEmail = e;
        gotPassword = p;
        return 'uid-1';
      },
      nextPage: (uid) => Scaffold(body: Text('NEXT $uid')),
    )));
    await settle(t);
    await t.enterText(find.byType(TextField).first, '  a@b.com ');
    await t.enterText(find.byType(TextField).last, 'secret');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('NEXT uid-1'), findsOneWidget);
    // Same trimming as before this change.
    expect((gotEmail, gotPassword), ('a@b.com', 'secret'));
  });

  testWidgets('fields declare keyboard actions and autofill hints', (t) async {
    await t.pumpWidget(host(LoginPage()));
    await settle(t);
    final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.first.textInputAction, TextInputAction.next);
    expect(fields.first.autofillHints, contains(AutofillHints.username));
    expect(fields.last.textInputAction, TextInputAction.done);
    expect(fields.last.autofillHints, contains(AutofillHints.password));
    expect(fields.last.obscureText, isTrue);
  });

  testWidgets('show/hide password toggles and is labelled', (t) async {
    await t.pumpWidget(host(LoginPage()));
    await settle(t);
    expect(find.byTooltip('Show password'), findsOneWidget);
    await t.tap(find.byTooltip('Show password'));
    await t.pump();
    expect(t.widgetList<TextField>(find.byType(TextField)).last.obscureText,
        isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  for (final c in [
    (name: 'small phone', size: const Size(320, 480), scale: 1.0),
    (name: 'small phone, 200% text', size: const Size(320, 480), scale: 2.0),
    (name: 'landscape phone', size: const Size(640, 320), scale: 1.0),
    (name: 'tablet', size: const Size(900, 1200), scale: 1.0),
  ]) {
    testWidgets('no overflow: ${c.name}', (t) async {
      await t.pumpWidget(host(LoginPage(), size: c.size, scale: c.scale));
      await settle(t);
      expect(t.takeException(), isNull);
    });
  }
}
