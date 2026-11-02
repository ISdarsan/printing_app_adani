import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'business_time.dart';
import 'theme.dart';

/// Bills carry the SERVER time, but the day's totals (`dailyStats`), repayment
/// stats and the cash-closing record are filed under a day key taken from the
/// PHONE's clock. A phone with a wrong date (reset after a dead battery,
/// manual time) would file sales under the wrong day and make the dashboard,
/// the reports and the cash closing disagree.
///
/// This compares the phone's clock with a server-supplied time and blocks a
/// money write only when it would land on the wrong business day.
class ClockCheck {
  /// Phone time minus server time (positive = phone is ahead).
  final Duration skew;

  /// The phone's business day (IST) differs from the server's.
  final bool wrongBusinessDay;

  const ClockCheck({required this.skew, required this.wrongBusinessDay});

  /// Tolerance: a few seconds of difference around midnight is not worth
  /// stopping a sale for; a real clock error is minutes or more.
  static const Duration tolerance = Duration(minutes: 2);

  /// True when a write filed under the phone's day would be on the wrong day.
  bool get blocksWrites => wrongBusinessDay && skew.abs() > tolerance;

  /// Human text for the staff, e.g. "about 1 day ahead".
  String get describeSkew {
    final a = skew.abs();
    final dir = skew.isNegative ? 'behind' : 'ahead';
    // Nearest unit ("about 2 days", not "1 day" for 1 day 23 h 59 min).
    if (a >= const Duration(hours: 20)) {
      final d = (a.inMinutes / Duration.minutesPerDay).round();
      return 'about $d day${d == 1 ? '' : 's'} $dir';
    }
    if (a >= const Duration(minutes: 50)) {
      final h = (a.inMinutes / Duration.minutesPerHour).round();
      return 'about $h hour${h == 1 ? '' : 's'} $dir';
    }
    final m = a.inMinutes < 1 ? 1 : a.inMinutes;
    return 'about $m minute${m == 1 ? '' : 's'} $dir';
  }
}

ClockCheck evaluateClock(
    {required DateTime deviceNow, required DateTime serverNow}) {
  return ClockCheck(
    skew: deviceNow.toUtc().difference(serverNow.toUtc()),
    wrongBusinessDay:
        BusinessTime.dateKey(deviceNow) != BusinessTime.dateKey(serverNow),
  );
}

class ClockGuard {
  ClockGuard._();

  /// How long one check stays valid.
  static const Duration freshFor = Duration(minutes: 10);

  static ClockCheck? _last;
  static DateTime? _lastAt;
  static Future<ClockCheck?>? _inFlight;

  /// Test hooks.
  static Future<DateTime?> Function() fetchServerTime = _httpServerTime;
  static DateTime Function() now = DateTime.now;

  static void resetForTest() {
    _last = null;
    _lastAt = null;
    _inFlight = null;
    fetchServerTime = _httpServerTime;
    now = DateTime.now;
  }

  static bool get _isFresh =>
      _last != null && _lastAt != null && now().difference(_lastAt!) < freshFor;

  /// Start a check in the background (call when a money screen opens) so the
  /// first save does not have to wait for it.
  static void warmUp() {
    if (!_isFresh) unawaited(_refresh());
  }

  /// The current check: cached when fresh, otherwise fetched, waiting at most
  /// [wait]. `null` means "could not tell" (offline, timeout): never a reason
  /// to block a sale.
  static Future<ClockCheck?> current(
      {Duration wait = const Duration(milliseconds: 1500)}) async {
    if (_isFresh) return _last;
    final f = _refresh();
    try {
      return await f.timeout(wait);
    } on TimeoutException {
      return null;
    }
  }

  static Future<ClockCheck?> _refresh() {
    return _inFlight ??= () async {
      try {
        final server = await fetchServerTime();
        if (server == null) return null;
        final device = now();
        final check = evaluateClock(deviceNow: device, serverNow: server);
        _last = check;
        _lastAt = device;
        return check;
      } catch (_) {
        return null;
      } finally {
        _inFlight = null;
      }
    }();
  }

  /// The server's clock from the HTTP `Date` header of the Firebase endpoint
  /// the app already depends on. No extra package, no Firebase read.
  static Future<DateTime?> _httpServerTime() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client
          .headUrl(Uri.parse('https://firestore.googleapis.com/'))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      final header = res.headers.value(HttpHeaders.dateHeader);
      await res.drain<void>();
      return header == null ? null : HttpDate.parse(header);
    } finally {
      client.close(force: true);
    }
  }

  /// Use before a money write. Returns true when it is safe to continue; when
  /// the phone's date is wrong it explains why and returns false.
  static Future<bool> confirmSafe(BuildContext context) async {
    final check = await current();
    if (check == null || !check.blocksWrites) return true;
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.schedule_rounded, color: AppColors.accentOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text("This phone's date is wrong",
                style: AppText.style(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ),
        ]),
        content: Text(
          "This phone's clock is ${check.describeSkew}. Saving now would put "
          "this entry on the wrong day and today's totals would not match.\n\n"
          'Open Settings > Date & time and turn on "Automatic date & time", '
          'then try again. Nothing was saved.',
          style: AppText.style(
              color: AppColors.textSecondary, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK',
                style: AppText.style(
                    color: AppColors.accentBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return false;
  }
}
