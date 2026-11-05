# Reusable code

Pieces written for Senhorio that are general enough to lift into other
apps (or that new features here should use instead of re-writing). Check
this list before writing something new; add to it when you write
something reusable.

## Data and sync (any app that syncs records between NOSTR identities)

| What | Where | Reuse it for |
|---|---|---|
| `HlcClock` / `Hlc`: hybrid logical clock, sortable strings | `lib/core/hlc.dart` | Ordering edits from several devices without trusting their clocks |
| `Ledger`: signed NOSTR events (kind 30777) → tables with field-level last-writer-wins, plus authorization (owner/members) and pending events | `lib/data/ledger.dart` | Any multi-user, offline-first data set; add an entity to `schema.dart` and it syncs |
| `ZxStore`: ZX archive-database wrapper with migrations, a serialized transaction lock, meta key-value | `lib/data/zx_store.dart` | Local storage with full history (every commit is a generation) |
| `Checkpoints`: diff of every entity table between a past ZX generation and now, plus restore as a new signed change | `lib/domain/checkpoints.dart` | Audit trails or "what changed since…" in any ZX-backed app |
| `SyncEngine`: transport-agnostic sync protocol (hello vectors, event batches, blob requests), testable over an in-memory wire | `lib/sync/sync_engine.dart` | Syncing a `Ledger` over anything that can send JSON to a pubkey |
| `RnsNode`: Reticulum leaf node (all-hub mesh with reconnect, LAN, priority announce names, npub↔RNS binding in announce appData, LXMF send/receive) | `lib/sync/rns_node.dart` | Any app that needs to find peers by npub and send them encrypted messages over Reticulum |
| `KeyStore` / `SecureKeyStore` (OS keystore with a 0600-file fallback) / `MemoryKeyStore` | `lib/identity/identity_service.dart` | Keeping secrets (nsec, DB password, RNS identity) |
| `Identity`, `parsePubkey`, `shortNpub` | `lib/identity/identity_service.dart` | nsec/npub parsing, signing and display |

| `BackgroundSync` (Dart) + `SyncService.kt` / `MainActivity.kt` (cached engine, foreground service type connectedDevice, native heartbeat `onTick`) | `lib/platform/background.dart`, `android/app/src/main/kotlin/com/x1watt/senhorio/` | Keeping any Dart networking alive on Android with the app closed |

| `SqlBackend` + `openBackend` (conditional import: `.zx` file natively, ZX SQL engine in a dart2wasm Web Worker on the web) | `lib/data/sql_backend*.dart`, `web_engine/db_worker.dart`, `tool/build_web.sh` | Running ZX SQL in a Flutter web build (dart2js has no 64-bit ints; the worker does) |

## Domain helpers

| What | Where | Reuse it for |
|---|---|---|
| `Recurrence` + `Frequency` (weekly/monthly/quarterly/yearly, day clamped to month end, start/end) | `lib/domain/recurrence.dart` | Rent, recurring bills, any schedule |
| `leaseStatus` (periods vs payments, partial payments, overpayment carry, grace days) | `lib/domain/rent_schedule.dart` | Anything "expected vs paid" per period |
| `CategoryLearner` (naive Bayes over words, amount bucket, place, unit; vendor+similar-amount boost; keyword priors) | `lib/domain/category_learner.dart` | Auto-categorising transactions or documents |
| `parseMoney` / `formatMoney` (int cents; accepts `1.234,56` and `1,234.56`) | `lib/core/money.dart` | Money input in PT/EN |
| `isoDate`, `monthKey`, `daysInMonth` | `lib/core/dates.dart` | Dates stored as text |
| `monthlyTotals`, `byCategory`, `utilitySeries`, `occupancy`, `collection` | `lib/domain/stats.dart` | Aggregations for charts |

## UI

| What | Where | Reuse it for |
|---|---|---|
| `FieldSpec` + `EntityForm` / `showEntityForm` (text, money, int, decimal, date, choice, toggle, with validation) | `lib/ui/widgets/entity_form.dart` | Every simple create/edit form: describe its fields, don't write a new form |
| `editEntity` (shows the form, sends only changed fields as a signed upsert) | `lib/ui/forms.dart` | Editing any synced entity |
| `LiveFuture` (reloads when the ledger revision changes) | `lib/ui/widgets/common.dart` | Any screen showing ledger data |
| `confirm`, `guarded`, `EmptyState`, `SectionHeader`, `CategoryAvatar`, `context.l / app / money / toast` | `lib/ui/widgets/common.dart` | Common dialogs and widgets |
| `AttachmentThumb` + `shrinkImage` (JPEG ≤1600 px in an isolate) | `lib/ui/screens/expenses.dart` | Showing and storing photos and PDFs by SHA-256 |

## Candidates (not yet extracted)

- `AttachmentThumb` and the photo picking in `ExpenseForm` could move to
  `lib/ui/widgets/attachments.dart` once a second screen needs receipts
  (for example, the email/documents archive).
- The building/expense "filter chips" row appears in Expenses and Stats;
  extract a `BuildingFilter` widget if a third screen uses it.
