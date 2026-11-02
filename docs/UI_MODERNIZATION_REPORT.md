# UI Modernization Report

Branch `feature/ui-modernization-performance`. Read `UI_UX_AUDIT.md` for the per-screen detail.

## Honest scope statement

- **No screenshots were captured and no screen was run or visually inspected.** There are therefore no before/after images. Everything below is described from source and from widget tests that render components in a test harness at 320×480, 360×640, 640×320 (landscape), 900×1200 and with 160–200% text.
- I did **not** redesign the app from scratch. The existing design system (`theme.dart`: dark palette, bundled Inter font, solid cards with hairline borders, one brand hue, gradient button) already follows the stated direction (minimal, restrained, few colours, no heavy shadows). Rebuilding it would add risk to a live POS without evidence of benefit. The work focused on defects and gaps found by measurement.

## Design system additions

| Component | File | Notes |
|---|---|---|
| Loading view | `lib/state_views.dart` `AppLoading` | optional message, announced to screen readers |
| Empty state | `AppEmptyState` | icon, title, hint, optional action |
| Error state | `AppErrorState` | plain-language message (`friendlyErrorMessage`), "Try again" button ≥ 48 px high, `inline` mode for use inside columns |
| Retry for stateless screens | `RetryScope` | re-creates the builder to re-open a listener or fetch |
| One-line async helper | `asyncStateView` | loading or error view, else `null` |
| Stream lifecycle | `lib/stream_cache.dart` | not visual, supports the above |
| Colour | `theme.dart` `textHint` | contrast 2.8:1 → 4.6:1 |

No UI package was added. Nothing new in `pubspec.yaml`.

## Before / after (described, not pictured)

| Area | Before | After |
|---|---|---|
| Failed load | spinner forever, blank, ₹0 figures or text such as `Error: [cloud_firestore/permission-denied] …` | icon, "Could not load", one plain sentence (access vs connection vs other) and a Try again button |
| Cash closing | form shown with expected cash ₹0 until data arrived or if loading failed | form appears only once the real figure is known; otherwise loading or error with Retry |
| Bill detail | any failure said "Bill not found." | failure says could not load + Try again; "not found" only when the bill really does not exist |
| Cart row | long item name overflowed the screen | name wraps to two lines with ellipsis |
| Full/Half, +/-, remove | small tap areas, no labels | full-row or 44 px tap areas with screen-reader labels; visuals unchanged |
| Login | mouse-only flow | keyboard next / Enter to sign in, autofill hints, clear message for empty fields, password-eye tooltip |
| Secondary text | low contrast hint colour | passes WCAG AA |

## What was deliberately NOT changed

Business logic, Firestore collections and document shapes, financial calculations, authentication and role logic, Android signing, printing/Bluetooth code, Excel generation, security rules, indexes. A source-level test still guards the admin-only menu delete and the organisation-fund wording.

## Not done from the brief (and why)

| Item | Reason |
|---|---|
| Admin and cashier dashboard redesign (new layout) | Would need visual iteration on a device; existing hierarchy is already card-based. Risk to a live system without being able to see it. Listed as next step. |
| Widget tests for dashboards, customer search, repayment dialog, cash closing page | These screens create Firestore streams directly; there is no injection point and Firestore cannot be faked without refactoring. Their behaviour is guarded by source tests and the emulator suites. |
| Tablet / desktop layouts | App is portrait-locked and phone-first; no evidence tablets are used. |
| Raising the smallest fonts | Needs device QA for overflow. |
| Screenshots and visual QA | Not possible in this session. |
| Real-device checks (printer, Bluetooth, low-end performance, airplane mode) | Outstanding; see the final report. |
