# Senhorio

Shared accounting for rented buildings, for two or more people. Runs on
Android and desktop (Linux, Windows, macOS).

- **Buildings → apartments → rooms**, each room rented (with a lease) or
  kept empty.
- **Tenants and leases:** the rent amount, frequency
  (weekly/monthly/quarterly/yearly), due day, grace days and deposit.
  The app shows **who is late** and by how much, and accepts partial
  payments.
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
  encrypted over **Reticulum** (public hubs + local network). The owner of
  a building adds members by npub and can revoke them. On Android an
  optional foreground service keeps syncing with the app closed. See
  [docs/sync-protocol.md](docs/sync-protocol.md).
- **Nothing is lost:**
  - Data lives in a **ZX** archive-database that keeps every version.
  - Deletes are soft.
  - **Checkpoints** show everything added, changed or deleted since then,
    and by whom, with one-tap restore.
  - An automatic checkpoint is taken daily.
  - The backup export copies the whole history.
- Portuguese and English.
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

The Android APK is built by GitHub Actions (`.github/workflows/android.yml`)
on every push to `main` (download it from the run's artifacts) and is
attached to the release when a `v*` tag is pushed.

Reusable pieces are listed in [docs/reusable.md](docs/reusable.md).
