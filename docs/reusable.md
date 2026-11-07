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
| `Role` + `RoleRules` (owner/admin/mod/user/worker: `canGrant`, `canManage`, `isStaff`, `isPartial`) and `Ledger.roleAt` (role as of an HLC, by folding membership events); per-role field whitelists (`tenantOwnFields`, `workerTaskFields`) checked in `Ledger._authorize` | `lib/domain/roles.dart`, `lib/data/ledger.dart`, `lib/data/schema.dart` | Role-based permissions in any signed-event ledger, with revocations that keep earlier changes valid, and "may change only these fields of their own row" rules |
| `Invites`: short single-use codes found through a 1-byte announce tag, joined over LXMF (`normalizeInviteCode`, `inviteTag`) | `lib/sync/invites.dart`, `RnsNode.setInviteTags` / `peersWithTag` | Pairing two Reticulum apps with a code read aloud, without exchanging keys first |
| `PartialScope` (`SyncEngine.scopeFor`, per role, including the global scope) + `skip` ranges (`hidden_ranges` counted as held in `SyncEngine.vector`) | `lib/sync/sync_engine.dart` | Partial replication of a sequenced log without gaps that make peers re-ask forever |
| `blobFields` + `attachmentHashes` (which columns hold attachment hashes, as a list or one sha) | `lib/data/schema.dart`, `lib/sync/sync_engine.dart` | Adding a photo column to any entity makes the sync fetch its blob |
| `profiles` (global self-owned row per pubkey) + `Queries.people` / `Person` (nickname > profile > member name, with photo) + local `nicknames` table | `lib/data/schema.dart`, `lib/data/queries.dart` | Showing people by name in any multi-user app, with private per-device labels |
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
| `confirm`, `guarded`, `EmptyState`, `SectionHeader`, `CategoryAvatar`, `StaffOnly`, `context.l / app / money / toast` | `lib/ui/widgets/common.dart` | Common dialogs and widgets; `StaffOnly` hides write buttons from tenant-only users |
| `inviteToBuilding` / `showInviteCode` / `OpenInvites` / `joinWithCode` | `lib/ui/screens/invites.dart` | Invite UI: role picker, big code display, open codes list, join with progress |
| `AttachmentList` / `AttachmentThumb` / `pickAndStoreAttachment` / `shrinkImage` (camera, gallery, file; JPEG ≤1600 px; stored by SHA-256) | `lib/ui/widgets/attachments.dart` | Any entity with photos or PDFs (receipts, ID documents, task photos) |
| `pickPhoto` / `StoredImage` / `PhotoAvatar` / `PhotoBanner` / `setEntityPhoto` (one presentation picture per row, by SHA-256) | `lib/ui/widgets/attachments.dart` | A picture on any entity: list avatar, screen banner, "set photo" action |
| `PersonAvatar` / `personName` / `editNickname` | `lib/ui/widgets/people.dart` | Showing and privately labelling people |
| `ProfileScreen` | `lib/ui/screens/profile.dart` | A self-edited name + picture screen |
| `TasksTab` / `TaskScreen` / `editTask` / `TaskStatusChip` (assign → photo evidence → approve/reject, repeat next week/month) | `lib/ui/screens/tasks.dart` | Any "work order with proof and approval" flow |
| `FieldType.datetime` in `EntityForm`, `isoDateTime`, `formatDateTime` / `formatTimeRange` | `lib/ui/widgets/entity_form.dart`, `lib/core/dates.dart`, `lib/ui/widgets/common.dart` | Date-time fields and ranges in forms and lists |
| `RoomMosaic` (coloured tiles, staggered grow-in, pulsing alert) | `lib/ui/widgets/room_mosaic.dart` | Any at-a-glance status board |
| `Backups` (export to public Downloads via MediaStore on Android / save dialog on desktop; `verify` → `stage` → `commit` restore with the previous archive kept; one pasted restore key parsed from free text) + `AppState.onRestart` / `shutdown` | `lib/platform/backup.dart`, `MainActivity.kt` (`saveToDownloads`), `lib/app_state.dart`, `lib/main.dart` | Backup/restore of any single-file database, with an in-place app restart |
| `UpdateService` + `checkForUpdates` dialog + `installApk` channel (GitHub latest release → download → system installer) | `lib/platform/updates.dart`, `lib/ui/screens/update_dialog.dart`, `MainActivity.kt` | Self-updating Android apps published on GitHub releases |
| `depositHeld`, `isRentPayment`, `paymentKinds` | `lib/domain/rent_schedule.dart` | Deposits/provisions kept apart from rent |

## Tests

| What | Where | Reuse it for |
|---|---|---|
| `Wire`: in-memory network for `SyncEngine`s (JSON round-trip, `settle()`) | `test/wire.dart` | Any multi-peer sync test |
| Widget test harness for screens on a real ZX store (`settle()` pumping in small real-time steps until no spinner; `MaterialApp(key: UniqueKey())` per screen) | `test/tasks_screen_test.dart` | Testing any `LiveFuture` screen against real data |

## Candidates (not yet extracted)
- The building/expense "filter chips" row appears in Expenses and Stats;
  extract a `BuildingFilter` widget if a third screen uses it.
