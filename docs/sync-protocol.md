# Senhorio sync

## Data model: a signed event log

Every change is a NOSTR event (NIP-01, kind **30777**), signed with the
user's nsec:

```json
{"kind": 30777, "pubkey": "<hex>", "created_at": 1762380000,
 "tags": [["b", "<building id>"], ["seq", "12"], ["hlc", "1762380000123-0000-1a2b3c4d"], ["e", "expenses"]],
 "content": "{\"entity\":\"expenses\",\"id\":\"…\",\"op\":\"upsert\",\"fields\":{\"amount_cents\":4200}}"}
```

- `b` is the building the change belongs to (`""` for global data:
  categories).
- `d` is the device that wrote the event (random id kept with the keys).
  One npub may run on several devices: a restored nsec on a new phone, a
  laptop and a phone. Each device keeps its own sequence.
- `seq` counts per (author, device, building), starting at 1, so a peer
  can say exactly what it holds. Sync vectors are keyed `author/device`.
- `hlc` is a hybrid logical clock. Each field keeps the HLC of its last
  write (`field_hlc`), and the higher HLC wins. Two people editing
  different fields of the same row both keep their change.
- `op: delete` only sets `deleted = 1`. Nothing is ever removed from the
  tables. A restore is an `upsert` with `deleted: 0`.

Events and their projection are committed in one ZX transaction, so one
user action makes one ZX generation. Checkpoints compare any past
generation with now (`AS OF GENERATION`).

## Authorization (enforced by every receiver)

- A building exists from the event that creates it. Its author is its
  **owner**, and the owner cannot change later.
- `members` rows (add/revoke) are accepted only from the owner.
- Other changes are accepted from the owner or from a live member. A
  revoked member's changes made before the revocation's HLC stay valid.
- An event whose author is not (yet) known as a member is stored as
  `pending` and re-checked when membership changes. This happens because
  events can arrive out of order.
- Global `categories` events come from anyone who is a member of some
  building we hold.

## Transport: Reticulum + LXMF

- **Interfaces:**
  - TCP uplinks to every configured hub at once (a mesh, re-dialed every
    30 s).
  - LAN UDP broadcast on port 42671, used for discovery only.
- **Discovery:** each node announces `senhorio/sync`.
  - The appData is the user's pubkey (32 bytes) followed by a Schnorr
    signature (64 bytes) over `sha256("senhorio-bind" || rns identity hash)`.
  - Receivers verify it, so an npub can only be claimed by its key holder.
  - A node re-announces 5 s after it hears a new peer, so newcomers learn
    it quickly.
- **Priority names:** `senhorio/sync` and `lxmf/delivery` are marked as
  priority announce names. Otherwise reticulum-dart sheds unknown
  announces down to one per 3 s.
- **Messages:** LXMF (title `senhorio/1`, JSON content) to the peer's LXMF
  delivery destination.
  - The link is end-to-end encrypted (X25519 + AES-256 per link).
  - Large messages go as Resources.
  - A message is only accepted from a node whose npub binding we verified.

## Protocol messages

| `t` | Fields | Meaning |
|---|---|---|
| `hello` | `first`, `v: {building: {"author/device": seq}}` | What I hold, as the highest seq per author with no gaps. The receiver sends what is missing for buildings the sender may see. If `first` is set, it also answers with its own hello. |
| `events` | `e: [event…]` | Up to 48 KB of signed events. |
| `need` | `sha: [...]` | Receipts referenced by expenses but not held. |
| `blob` | `sha, mime, data` | One receipt (base64). The receiver checks the SHA-256. |

When the owner adds a member, the owner sends that member's device the
building's whole history. A user's own other devices are partners too:
a device that just imported the nsec says hello to every node announcing
the same npub and receives everything that npub may see. Changes made on one device are pushed straight
away to every partner device that is online. Partners also say hello
every 3 minutes and whenever one is discovered.

## Testing

- `test/sync_test.dart`: in-memory wire. Covers a member joining, live
  push, receipts, offline catch-up, a stranger being refused and
  revocation.
- `test/rns_sync_test.dart`: two real nodes through a public hub:
  `SENHORIO_HUB=rns.wisco.network:4242 flutter test test/rns_sync_test.dart`.
