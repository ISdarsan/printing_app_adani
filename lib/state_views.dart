import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Plain-language text for a failed load or save. Staff never see Firebase
/// terms. [action] is "loading", "saving"... and only affects the fallback text.
String friendlyErrorMessage(Object? error, {String action = 'loading'}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return 'You do not have access to this information. '
            'Please ask the admin to check your account.';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return 'Cannot reach the server. Check the internet connection '
            'and try again.';
      case 'failed-precondition':
        // Firestore: "The query requires an index". A one-time database
        // setup, not something a cashier can fix by retrying.
        return 'This screen needs a one-time database setup that is not '
            'finished yet. Please tell the admin.';
    }
  }
  return 'Something went wrong while $action. Please try again.';
}

/// Centered progress indicator with an optional message.
///
/// A spinner that never ends (no connection and nothing cached) used to leave
/// staff guessing. After [slowAfter] it adds: "Still loading. Check your
/// internet connection."
class AppLoading extends StatefulWidget {
  final String? message;
  final Duration slowAfter;
  const AppLoading(
      {super.key, this.message, this.slowAfter = const Duration(seconds: 8)});

  @override
  State<AppLoading> createState() => _AppLoadingState();
}

class _AppLoadingState extends State<AppLoading> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _slow
        ? 'Still loading. Check your internet connection.'
        : widget.message;
    return Center(
      child: Semantics(
        liveRegion: true,
        label: text ?? 'Loading',
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              if (text != null) ...[
                const SizedBox(height: 12),
                Text(text,
                    textAlign: TextAlign.center,
                    style: AppText.style(
                        color: _slow
                            ? AppColors.accentOrange
                            : AppColors.textSecondary,
                        fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StateBody extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final Widget? action;
  final bool inline; // true inside a Column / unbounded height
  const _StateBody({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.action,
    this.inline = false,
  });

  Widget _content() => Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppText.style(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    style: AppText.style(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45)),
              ],
              if (action != null) ...[
                const SizedBox(height: 18),
                action!,
              ],
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (inline) return Center(child: _content());
    // Scrollable + centered: never overflows on small phones, large text
    // scale or landscape, and works inside RefreshIndicator parents.
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: c.hasBoundedHeight ? c.maxHeight : 0),
          child: Center(child: _content()),
        ),
      ),
    );
  }
}

/// "Nothing here yet" view.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool inline;
  const AppEmptyState({
    super.key,
    this.inline = false,
    this.icon = Icons.inbox_rounded,
    required this.title,
    this.message = '',
    this.action,
  });

  @override
  Widget build(BuildContext context) => _StateBody(
        icon: icon,
        color: AppColors.accentBlue,
        title: title,
        message: message,
        action: action,
        inline: inline,
      );
}

/// Failed-load view with a Retry button (a failure is never shown as empty or
/// as zero money).
class AppErrorState extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;
  final bool inline;
  const AppErrorState(
      {super.key, this.error, this.onRetry, this.inline = false});

  @override
  Widget build(BuildContext context) => _StateBody(
        icon: Icons.cloud_off_rounded,
        color: AppColors.accentOrange,
        inline: inline,
        title: 'Could not load',
        message: friendlyErrorMessage(error),
        action: onRetry == null
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 140),
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ),
      );
}

/// One-liner for StreamBuilder/FutureBuilder: returns the loading or error view
/// when the snapshot has no usable data yet, otherwise `null` (render data).
///
///     final state = asyncStateView(snap, onRetry: _retry);
///     if (state != null) return state;
Widget? asyncStateView(AsyncSnapshot<dynamic> snap,
    {VoidCallback? onRetry, String? loadingMessage}) {
  if (snap.hasError) return AppErrorState(error: snap.error, onRetry: onRetry);
  if (!snap.hasData) return AppLoading(message: loadingMessage);
  return null;
}

/// Gives a stateless screen a working Retry: put the StreamBuilder/FutureBuilder
/// inside [builder] and give it `key: ValueKey(attempt)`. Calling `retry`
/// re-creates it, which opens a fresh listener / fetch.
class RetryScope extends StatefulWidget {
  final Widget Function(BuildContext context, int attempt, VoidCallback retry)
      builder;
  const RetryScope({super.key, required this.builder});

  @override
  State<RetryScope> createState() => _RetryScopeState();
}

class _RetryScopeState extends State<RetryScope> {
  int _attempt = 0;

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        _attempt,
        () => setState(() => _attempt++),
      );
}

/// "Coming soon" notice for a feature that is not finished yet. Used instead of
/// opening a half-built feature.
Future<void> showComingSoonDialog(
  BuildContext context, {
  required String feature,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.hourglass_top_rounded, color: AppColors.accentBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Coming soon',
              style: AppText.style(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ),
      ]),
      content: Text(
        '$feature is not available yet. We are still building it and it will '
        'arrive in a future update.',
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
}
