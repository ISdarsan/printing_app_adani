# Sync Reliability Report (B-12)

Firestore persistence is untouched (offline cache stays enabled). This work adds honest status reporting and safe write protocols on top of it.

## 1. The four states (plus one neutral)
Implemented in `lib/sync_status.dart` (`SyncTracker`) and shown by `lib/sync_banner.dart` as a slim strip above every screen. **Nothing is shown when everything is saved.**

| State | When | Banner text |
|---|---|---|
| Synced | server reachable and nothing waiting or failed | (hidden) |
| Sync pending | online, with writes the server has not yet acknowledged | "Saving N change(s)..." |
| Offline | no server connection | "Offline. Showing saved data, which may be out of date." / "Offline. N change(s) will sync when you reconnect." |
| Sync failed | at least one write failed and was not dismissed | "N change(s) not saved. Tap to review." |
| Connecting (internal) | before the first server answer | hidden, and never reported as synced |

Precedence: failed > offline > pending > connecting > synced. Tapping the strip opens a sheet listing each waiting or failed item with Retry (only where safe) and Dismiss.

## 2. How "success" is decided
- A write counts as saved **only when its Future completes**. For `set/add/update` Firestore completes that Future when the **server** acknowledges, not when it is queued locally, so offline writes correctly remain pending. Screens that used to say "Expense logged!" immediately after an `await` still only say it after acknowledgement; if no acknowledgement arrives within 8 s the screen says "Saved on this device, not confirmed yet" (orange) and releases the form, while the write stays tracked in the background.
- Connection state is derived from a metadata listener on the user's own staff document (`ConnectionProbe`): any snapshot with `isFromCache == false` proves the server answered; cache-only for 5 s means offline; a fresh server snapshot after reconnecting flips back to online. Pure rule tested in `connectionFromMetadata`.
- **Cached values are never presented as current:** while offline the strip says the screen shows saved data that may be out of date. Writes queued by a previous session are discovered through `waitForPendingWrites()` and shown as pending only if still unconfirmed after 1.5 s (no flash on a normal start).
- The cashier "today" card shows a dash until its first answer or on error, never an invented zero.
- Analytics and export reads use `Source.server`; offline they fail with a clear message instead of returning cached numbers. Staff authorisation at sign-in also reads from the server.

## 3. Write paths and their protocol
| Operation | Firestore call | Idempotent? | Offline behaviour | Retry |
|---|---|---|---|---|
| **Bill** | transaction (bill + dailyStats + customer + counter) | No (server-assigned bill number) | transaction fails; nothing saved; cart kept | **Create-once**: stable `clientRequestId` stored on the bill; before any repeat the app asks the server whether a bill with that id exists (branch-scoped equality query). Found = reuse it (no second bill); not found = create with the same id. Server check failing aborts rather than risking a duplicate |
| **Credit repayment** | transaction | No | fails cleanly | Same create-once protocol with `clientRequestId` on the repayment |
| **Cash closing** | transaction on deterministic id (`branch_date`) | Yes by id | fails cleanly | A repeat that finds its own earlier submission (same user, same amount) reports success instead of "already submitted"; a different submission is still refused |
| **Expense** | `set` on a pre-chosen id | Yes | queued by Firestore; shown as pending; message says "not confirmed yet" | Banner Retry is safe (same id). If the first attempt did commit and the acknowledgement was lost, the repeat is denied as an update (cashiers may only create), so the app reads the document from the server and treats "exists" as saved (proved in the emulator) |
| **Admin notice** | `set` on a pre-chosen id | Yes | as expense | as expense |
| Duplicate taps | | | | each flow has a re-entry guard (`_isSaving`, `_isProcessing`, `_isSubmitting`, `_isLoading`, and the tracker refuses the same key while in flight) |

Why transactions are not queued offline: bill numbers come from a per-branch counter read and incremented inside the transaction, so a bill cannot be numbered without the server. This is deliberate and unchanged; **offline billing would need a different numbering scheme (a business decision, not made).**

The financial rule: **the tracker never re-runs a bill or repayment by itself** (`safeToRetry: false`). The only retry is the cashier tapping Save again, which goes through the server check first. The banner sheet shows no Retry button for these, only guidance to check whether it was recorded.

## 4. Reconnection behaviour
Offline -> online with queued writes: Firestore flushes them by itself; each tracked Future completes as the server acknowledges; the strip goes "Offline" -> "Saving N" -> hidden. Verified in unit tests with controllable futures (queued, offline, reconnect, acknowledge). A write that the server rejects after reconnecting (for example rules) ends as "not saved", never silently lost.

## 5. Test evidence
- `test/sync_status_test.dart`: **40 tests**: all state transitions, no success before acknowledgement, offline/reconnect/flapping, restored pending writes, metadata mapping, failure recording and rethrow, retry safe vs unsafe (financial never re-run: asserted `calls == 1`), duplicate prevention, create-once (lost acknowledgement creates nothing; genuine failure retries with the same id; changed cart = new attempt; failing server check aborts), idempotent set, tracked write timing (confirmed / pending offline / late failure / immediate failure / double tap), banner UI (hidden when synced, offline text, Retry for safe ops works, none for financial).
- Emulator (real rules): `clientRequestId` can be stored and verified with a branch-scoped query; an unscoped or other-branch check is denied; a repeat of a committed expense create is denied for a cashier, and a server read confirms it.

## 6. Not covered (be aware)
- **No device test.** The Firestore listener, `waitForPendingWrites`, real airplane-mode transitions and the 5 s grace period have not been observed on a phone. Only the pure decision functions and the UI against a fake tracker are tested.
- The probe depends on the staff document listener; if that document is unreadable the state stays "connecting" (no banner) rather than guessing.
- Not tracked (writes still behave as before, without the strip): menu add/edit/delete, monthly fund updates, canteen and staff administration, notice read receipts. They are idempotent or admin-only; extending the tracker to them is mechanical.
- Reads in other screens still use the default source (cache allowed); the offline strip is the indicator for those.
- A bill saved while the app is killed mid-transaction ends either committed or not; on the next Save the server check resolves it only if the cart content is identical (the request id lives in memory). A killed app that loses its cart also loses that link, so the cashier should look in Today's Sales before re-entering.
- Clock: day keys and ranges use the device clock converted to IST; a badly wrong device clock can mis-date a bill (unchanged risk).
