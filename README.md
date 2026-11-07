# Senhorio

Shared accounting for rented buildings, for two or more people. Runs on
Android and desktop (Linux, Windows, macOS).

- **Buildings → apartments → rooms**, each room rented (with a lease) or
  kept empty.
- **Tenants and leases:** the rent amount, frequency
  (weekly/monthly/quarterly/yearly), due day, grace days and deposit.
  The app shows **who is late** and by how much, and accepts partial
  payments. Deposits (caução) and provisions are tracked apart from rent
  and returned or kept for repairs when the tenant leaves. Each room shows
  its occupation history; the tenant's phones and email are one tap away,
  and their identification documents can be attached.
- A building opens with an animated board of its rooms: green when the
  rent is in order, red when overdue, grey when empty.
- **Expenses** with **receipt photos or PDFs**, per building, apartment or
  room. There are 13 default categories (water, electricity, gas, internet,
  condo fees, material, repairs, cleaning, food, furniture, insurance,
  taxes, other), plus your own.
- **Self-learning categories:** each new expense gets suggestions from the
  vendor, description, amount and place, learned from what was entered
  before. Recurring vendors at a similar amount are recognised.
- **Recurring bills** (water, electricity, internet…) with "due soon" on
  the overview and one-tap registration.
- **Statistics:**
  - income vs expenses per month, by category
  - utility trends with cost per kWh/m³ and per rented room
  - occupancy and rent collected
- **Sync between people** identified by NOSTR keys (npub/nsec), end-to-end
  encrypted over **Reticulum** (public hubs + local network).
- **Invite codes and roles:**
  - The owner, an admin or a mod makes a short code (like `AB49`) for a
    role. Anyone with the app types it in (Buildings → key icon) and
    joins. A code works once, for 24 hours.
  - **Admins** are co-owners. **Mods** run the day to day and can invite
    tenants.
  - **Tenants** (users) see only their own lease, room and payments, and
    whether the rent is late. They can change their own phone and email
    and add their identification documents; everything else is read-only.
    Other tenants' data and the expenses never reach their phone.
  - **Workers** (cleaning, repairs) see only the tasks given to them.
  - Members can also be added by npub. Roles can be changed and members
    revoked.
- **Shared bills** (building → Shared bills): a manager enters a bill
  (the energy of an apartment, say), picks the group (that apartment's
  tenants, or the whole building's) and the amount is split evenly. Each
  tenant marks their part "I have paid"; a manager confirms it, after
  which the tenant can no longer touch it. Payments to confirm show on
  the dashboard. A shared bill can be registered as an expense of the
  building in one tap (and an expense can be split between the tenants),
  the two stay linked, and the bill shows how much the tenants paid back.
- **Tenant details approval:** once a manager approves a tenant's
  details (lease card → "Approve the tenant's details"), the tenant can
  no longer change or erase them; only managers can.
- **Overdue warnings for tenants:** late rent and unpaid shared bills
  past their date show as a red banner on the tenant's screens and, on
  Android, as a permanent notification until the managers register the
  payment.
- **Profiles and nicknames:** everyone sets a name and a picture (More →
  My profile) that the people they share buildings with see. Managers can
  also give a member a nickname of their own, kept only on their device.
- **Work and cleaning tasks** (building → Tasks): a task has a place, a
  time range and a worker. The worker takes photos of the finished work
  and marks it done; an owner, admin or mod approves or rejects it. Work
  waiting for approval shows on the dashboard. A task can be repeated to
  the next week or month in one tap.
- **Pictures** of a building, an apartment or a room, shown on their
  screens and lists.
- On Android an
  optional foreground service keeps syncing with the app closed. See
  [docs/sync-protocol.md](docs/sync-protocol.md).
- **Nothing is lost:**
  - Data lives in a **ZX** archive-database that keeps every version.
  - Deletes are soft.
  - **Checkpoints** show everything added, changed or deleted since then,
    and by whom, with one-tap restore.
  - An automatic checkpoint is taken daily.
  - **Backup and restore** (More → Export backup / Restore backup): the
    whole archive with its history goes to the phone's Downloads folder
    (or a chosen file on desktop), which uninstalling the app keeps. The
    export shows a *restore key* (your nsec and the archive's password):
    keep it with the file, e.g. in a password manager. Restoring on a
    fresh install brings back the data and the identity.
- Portuguese and English; dark (black) theme.
- **Updates:** the app checks GitHub releases once a day; on Android it
  downloads the new APK and opens the installer.
- One identity (nsec) can be restored on another device, and several
  devices of the same person sync with each other like members do.
- Emails and documents: the structure is in place (`documents` table);
  import comes later.

## Build

Depends on sibling checkouts: `../zx` and `../../xprs/reticulum-dart`.
On the shared Pi, run builds and tests through `xbuild`.

- Unit and in-memory sync tests: `flutter test`
- Real-network sync test: set `SENHORIO_HUB=rns.wisco.network:4242`, then
  run `flutter test test/rns_sync_test.dart`
- Apps: `flutter build linux` or `flutter build apk`
- Browser preview: `tool/build_web.sh`, then `tool/serve_web.py 8080` and
  open http://localhost:8080/. The web build keeps its data in memory (the
  ZX SQL engine runs in a WebAssembly worker), starts with sample data and
  has no Reticulum sync (browsers have no sockets); it is for trying the UI.

Android release signing: the key lives outside the repo
(`~/.data/senhorio-release.p12`, back it up: losing it means no
installed app can update again). Locally, `android/key.properties` (ignored
by git) points to it. CI writes that file from the repository secrets
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and
`ANDROID_KEY_ALIAS`, and refuses to publish a tagged release without them.

The Android APK is built by GitHub Actions (`.github/workflows/android.yml`)
on every push to `main` (download it from the run's artifacts) and is
attached to the release when a `v*` tag is pushed.

Reusable pieces are listed in [docs/reusable.md](docs/reusable.md).
