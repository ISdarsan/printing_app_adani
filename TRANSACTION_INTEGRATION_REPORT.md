# Transaction Integration Report (Tasks 4 and 5)

## What was tested, and what that does and does not prove
`security-tests/transactions.test.mjs`: 26 tests on the **real Firestore emulator under the real `firestore.rules`**, synthetic data only, nothing near production.

**Important limit:** the Dart code cannot run against the emulator (there is no Flutter-to-emulator harness in this repo). The tests are therefore a **line-by-line port** of the exact logic of `_saveBill`, `_processRepayment`, `_submitReconciliation`, `planRepayment`, `AttemptTracker` and `createOnce`, written with the Firestore JS SDK. They prove the rules, the data semantics and the protocol. They do **not** execute the Dart code, and they do not exercise the Android SDK that the Flutter app uses. The Dart side of the same protocol is covered by 40 unit tests (`sync_status_test.dart`) and the arithmetic by `money_precision_test.dart`.

## Fault injection used
| Fault | How it was produced | Realism |
|---|---|---|
| Double tap, sequential | second call with the same request id | exact |
| Double tap / race, concurrent | two clients, two simultaneous transactions with one request id | exact (real concurrency on the emulator) |
| Lost acknowledgement | the transaction commits on the server, then the client treats the call as failed | **simulated at protocol level** (a deterministic network-level loss of only the commit response was not achievable) |
| Network interruption during save | a TCP proxy between client and emulator is **cut for real** (sockets destroyed, port closed), then restored | genuine connection loss |
| Offline queued writes | `disableNetwork()` for plain writes (expenses) | valid for writes |
| Reconnection | proxy restored / `enableNetwork()` | genuine |

Tooling caveat found on the way: in the JS SDK `disableNetwork()` does **not** stop `runTransaction` (it still reached the server in 464 ms), so it cannot model an offline phone for transactions. Cutting the socket does. On Android, Firestore transactions fail when offline; that has not been observed here.

## Results (26 of 26 pass)
| Requirement | Tests | Result |
|---|---|---|
| Bill: number, id, stats | cash bill saved once as number 1, bill id == request id, `dailyStats` and counter consistent; three sequential bills numbered 1-3 | pass |
| **Double tap** | same request id twice in sequence: second rejected, bill count 1, counter 1, stats unchanged | pass |
| **Double tap, concurrent** | two simultaneous saves with one request id: exactly one commits (counter 1, one bill, sales counted once) | pass |
| Different carts at once | both saved with numbers 1 and 2, no collision | pass |
| **Lost acknowledgement + retry with the same request id** | commit happened, client "failed"; second tap finds the bill by `clientRequestId` and creates nothing (creates == 1) | pass |
| Genuine failure then retry | nothing on server, retry creates exactly one bill with the same id | pass |
| **Network interruption during save** | connection cut: transaction rejects after about 12 s, **no bill, no counter, nothing queued**; after restoring, the retry (server check first, then create with the same id) saves exactly once; bills 2, sales 61, counter 2 | pass |
| Tampering | re-creating an existing bill id with other numbers is denied; the original is intact | pass |
| Branch isolation | a cashier cannot create bills for another branch | pass |
| Credit customer, new | first credit bill to a new customer works; the old read-a-missing-document pattern is denied | pass |
| Credit customer, race | customer created by another device in between: balance added, never overwritten | pass |
| **Repayment balance correctness** | part payment clears the oldest bill first; remaining 30.25; customer 30.25; cash and `creditReceived` up by 120.25; **sales and bill count unchanged** | pass |
| Exact payoff | all bills Paid, balance exactly 0 | pass |
| Paise accuracy | nine payments of 10.10 then the exact remainder 9.10: bill Paid, balance 0 | pass |
| **Repeated repayment submission** | same request id twice: balance reduced once, one repayment, `creditReceived` once | pass |
| Concurrent repayment | two simultaneous submissions: exactly one applied | pass |
| Repayment lost acknowledgement | retry finds the repayment, nothing applied twice | pass |
| Over-payment | refused by the rules; balance never negative | pass |
| Repayment during outage | fails cleanly, balances unchanged | pass |
| Cash closing | first closing works without reading a missing document; second refused; own repeat after a lost acknowledgement recognised; the create-only write cannot overwrite | pass |
| Today queries | own-branch "today" queries return nothing, not an error, before the first sale | pass |
| **Offline expense** | stays pending (not acknowledged), invisible to others, delivered once after reconnect; two taps still give one expense; repeat-after-commit denied then confirmed by a read | pass |

## Findings that changed the code
1. **Cashiers cannot read a document that does not exist** (verified on the real rules for `dailyStats`, `creditCustomers`, `bills`, `cashReconciliations`, `expenses`, `repayments`, `menuItems`, `notifications`; only `counters` allow it). Under the repository rules this means, before this change:
   - the first credit bill for a new customer (read of the missing customer inside the transaction) would be denied;
   - the first cash closing of a day (read of the missing closing inside the transaction) would be denied;
   - the closing screen's document streams would error and then stop, so it would not notice the closing being submitted;
   - the new dashboard card would show a dash all morning until the first sale.
   **Whether production is affected depends on its deployed rules, which have not been compared.** If production differs from the repository, these flows may have worked all along. The code is now correct under either variant: reads of possibly-missing documents were replaced by own-branch equality queries (which return an empty result), customers by a query-then-merge/increment write, closings by a query-then-create-only write.
2. **Duplicate prevention is now structural.** Bill and repayment document ids equal the request id. A second create is an *update* to the rules, which cashiers may not do, so it is rejected atomically and the whole transaction rolls back. This works with no read of a missing document and no race window.
3. Because two simultaneous attempts can now only fail with a permission error, the cashier message tells them to tap Save again, which first asks the server for the request id (tested).

## Not covered
- The Dart code itself against the emulator, and the Android Firestore SDK's behaviour (transaction timeout, queue behaviour, retry timing). 
- A network-level loss of only the commit response; the lost-acknowledgement case is simulated at protocol level.
- Real devices, real latency, the sync banner timing in real airplane mode (see CASHIER_DEVICE_TEST_PLAN.md).
- Production rules (comparison pending); results hold for the repository rules.
- App kill in the middle of a save: the request id lives in memory.

Re-run: `firebase emulators:exec --only firestore --project demo-test "cd security-tests && node --test --test-timeout=200000 transactions.test.mjs"` (use a free emulator port via a temporary config, as in TEST_RESULTS.md).
