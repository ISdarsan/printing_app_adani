import 'dart:async';

/// One page of results plus the opaque cursor for the next page.
class PageResult<T> {
  final List<T> items;

  /// Cursor to pass to the next call (for Firestore: the last document).
  final Object? cursor;

  /// True when the source may still have more items.
  final bool hasMore;
  const PageResult(this.items, this.cursor, this.hasMore);
}

typedef PageFetcher<T> = Future<PageResult<T>> Function(
    Object? cursor, int limit);

class PagedFetchResult<T> {
  final List<T> items;

  /// True when [maxItems] was reached and more data exists. The caller must
  /// tell the user the result is incomplete.
  final bool truncated;
  final int pages;
  final int retriedPages;

  /// Items skipped because their key was already seen (should stay 0 with a
  /// stable cursor; reported so tests and logs can prove it).
  final int duplicatesDropped;
  const PagedFetchResult(this.items,
      {required this.truncated,
      required this.pages,
      required this.retriedPages,
      required this.duplicatesDropped});
}

class PagedFetchException implements Exception {
  final Object cause;
  final int itemsLoaded;
  final int pagesLoaded;
  const PagedFetchException(this.cause, this.itemsLoaded, this.pagesLoaded);
  @override
  String toString() =>
      'Read failed after $itemsLoaded records ($pagesLoaded pages): $cause';
}

class PagedFetchCancelled implements Exception {
  final int itemsLoaded;
  const PagedFetchCancelled(this.itemsLoaded);
  @override
  String toString() => 'Cancelled after $itemsLoaded records';
}

/// Reads every page from [fetchPage] with the cursor of the previous page.
///
/// * A failing page is retried up to [maxRetries] times with a growing delay;
///   after that a [PagedFetchException] is thrown. No partial result is
///   returned silently: an interrupted export must not look complete.
/// * [isCancelled] is checked before every page ([PagedFetchCancelled]).
/// * [keyOf] enables duplicate detection across pages.
/// * [maxItems] bounds memory; hitting it sets `truncated`.
/// * A page that reports `hasMore` but returns no items and no cursor change
///   ends the loop (guards against an infinite loop).
Future<PagedFetchResult<T>> fetchAllPages<T>({
  required PageFetcher<T> fetchPage,
  int pageSize = 500,
  int maxItems = 200000,
  int maxRetries = 2,
  Duration retryDelay = const Duration(milliseconds: 400),
  bool Function()? isCancelled,
  String Function(T item)? keyOf,
  void Function(int itemsLoaded)? onProgress,
}) async {
  assert(pageSize > 0 && maxItems > 0);
  final out = <T>[];
  final seen = <String>{};
  Object? cursor;
  var pages = 0;
  var retried = 0;
  var dups = 0;
  var truncated = false;

  while (true) {
    if (isCancelled?.call() ?? false) throw PagedFetchCancelled(out.length);

    final remaining = maxItems - out.length;
    final limit = remaining < pageSize ? remaining : pageSize;

    PageResult<T>? page;
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        page = await fetchPage(cursor, limit);
        break;
      } catch (e) {
        lastError = e;
        if (attempt < maxRetries) {
          retried++;
          await Future<void>.delayed(retryDelay * (attempt + 1));
          if (isCancelled?.call() ?? false) {
            throw PagedFetchCancelled(out.length);
          }
        }
      }
    }
    if (page == null) {
      throw PagedFetchException(lastError ?? 'unknown error', out.length, pages);
    }
    pages++;

    for (final item in page.items) {
      if (keyOf != null && !seen.add(keyOf(item))) {
        dups++;
        continue;
      }
      out.add(item);
    }
    onProgress?.call(out.length);

    if (!page.hasMore) break;
    if (page.items.isEmpty && identical(page.cursor, cursor)) break;
    if (out.length >= maxItems) {
      truncated = true;
      break;
    }
    cursor = page.cursor;
  }

  return PagedFetchResult<T>(out,
      truncated: truncated,
      pages: pages,
      retriedPages: retried,
      duplicatesDropped: dups);
}
