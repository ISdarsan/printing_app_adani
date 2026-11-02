import 'package:flutter/material.dart';

import 'sync_status.dart';
import 'theme.dart';

/// Navigator key shared with MaterialApp so the details sheet can be opened
/// from the shell, which sits above the Navigator.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Wraps the whole app: shows a slim status strip while anything other than
/// "synced" is true, and nothing at all when everything is saved.
class SyncShell extends StatelessWidget {
  final Widget child;
  final SyncTracker tracker;
  const SyncShell({super.key, required this.child, required this.tracker});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final msg = tracker.message;
        if (msg.isEmpty) return child;
        return Column(
          children: [
            SyncBanner(tracker: tracker),
            Expanded(
              // the strip already covers the status bar area
              child: MediaQuery.removePadding(
                  context: context, removeTop: true, child: child),
            ),
          ],
        );
      },
    );
  }
}

Color _bannerColor(SyncState s) {
  switch (s) {
    case SyncState.failed:
      return AppColors.accentRed;
    case SyncState.offline:
      return AppColors.accentOrange;
    case SyncState.pending:
      return AppColors.accentBlue;
    case SyncState.connecting:
    case SyncState.synced:
      return AppColors.accentGreen;
  }
}

IconData _bannerIcon(SyncState s) {
  switch (s) {
    case SyncState.failed:
      return Icons.error_outline_rounded;
    case SyncState.offline:
      return Icons.cloud_off_rounded;
    case SyncState.pending:
      return Icons.sync_rounded;
    case SyncState.connecting:
    case SyncState.synced:
      return Icons.cloud_done_rounded;
  }
}

class SyncBanner extends StatelessWidget {
  final SyncTracker tracker;
  const SyncBanner({super.key, required this.tracker});

  @override
  Widget build(BuildContext context) {
    final s = tracker.state;
    return Material(
      color: _bannerColor(s),
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => showSyncDetails(context, tracker),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(_bannerIcon(s), color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tracker.message,
                    key: const Key('sync-banner-text'),
                    style: AppText.style(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white70, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Details sheet: what is waiting, what failed, and what can be retried.
Future<void> showSyncDetails(BuildContext context, SyncTracker tracker) {
  final ctx = appNavigatorKey.currentContext ?? context;
  return showModalBottomSheet<void>(
    context: ctx,
    backgroundColor: AppColors.bgCard,
    isScrollControlled: true,
    builder: (_) => SyncDetails(tracker: tracker),
  );
}

class SyncDetails extends StatelessWidget {
  final SyncTracker tracker;
  const SyncDetails({super.key, required this.tracker});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: tracker,
        builder: (context, _) {
          final ops = tracker.operations;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sync status',
                    style: AppText.style(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  tracker.connection == SyncConnection.offline
                      ? 'No connection to the server. What you see is saved data.'
                      : tracker.connection == SyncConnection.online
                          ? 'Connected to the server.'
                          : 'Checking the connection...',
                  style: AppText.style(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (ops.isEmpty)
                  Text('Nothing is waiting to be saved.',
                      style: AppText.style(
                          color: AppColors.textPrimary, fontSize: 13)),
                for (final op in ops)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                            op.status == OpStatus.failed
                                ? Icons.error_outline_rounded
                                : Icons.sync_rounded,
                            size: 18,
                            color: op.status == OpStatus.failed
                                ? AppColors.accentRed
                                : AppColors.accentBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(op.label,
                                  style: AppText.style(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                op.status == OpStatus.inFlight
                                    ? 'Waiting for the server to confirm'
                                    : op.safeToRetry
                                        ? 'Not saved: ${op.error}'
                                        : 'Not confirmed: ${op.error}\nCheck whether it was recorded before entering it again.',
                                style: AppText.style(
                                    color: AppColors.textSecondary,
                                    fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        if (op.status == OpStatus.failed) ...[
                          if (op.safeToRetry)
                            TextButton(
                              key: Key('retry-${op.key}'),
                              onPressed: () async {
                                try {
                                  await tracker.retry(op.key);
                                } catch (_) {}
                              },
                              child: const Text('Retry'),
                            ),
                          TextButton(
                            key: Key('dismiss-${op.key}'),
                            onPressed: () => tracker.dismiss(op.key),
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
