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
- Everyone else has a **role** in their `members` row (`lib/domain/roles.dart`):

  | Role | May |
  |---|---|
  | `owner` | everything |
  | `admin` | everything, including members, except the owner's own row |
  | `mod` (old rows: `member`) | all data, but not members, except adding and revoking tenants (`user`) |
  | `user` (tenant) | nothing: read-only, and receives only its own rows (see below) |

- A `members` row's id is always `building:pubkey`, and its pubkey never
  changes. Only the owner writes the owner's row.
- The role is judged **as of the event's HLC**: the receiver folds the
  member's applied membership events up to that HLC. Changes made before
  a revocation or a demotion stay valid.
- An event whose author is not (yet) known as a member is stored as
  `pending` and re-checked when membership changes. This happens because
  events can arrive out of order.
- Global `categories` events come from anyone who manages (not as a
  tenant) some building we hold.

## What a tenant receives

A tenant's device gets only the rows of the building it may see:

- the building row;
- its own `members` row and the rows of the owner, admins and mods;
- its `tenants` row (the member row's `tenant_id`);
- its leases, their payments, rooms and apartments.

The sender filters both the history (`hello`) and live pushes. For the
sequences it leaves out, it sends a `skip` with ranges, which the tenant
stores in `hidden_ranges` and counts as held in its vectors. Without it,
the gaps would make every hello resend everything after them. When a
lease or membership of the tenant's building changes, the tenant forgets
its ranges and says hello again, so newly visible rows (a new room) arrive.

## Invite codes

`lib/sync/invites.dart`. An owner, admin or mod makes a 4-character code
(alphabet without 0/O/1/I, e.g. `AB49`) for a role. Mods can only invite
tenants. A tenant code is linked to a tenant row.

1. The code lives only on the inviter's device (`invites` table). It
   works once, for 24 hours.
2. While it is open, the inviter's announce carries a 1-byte **tag**,
   `sha256("senhorio-invite:" + code)[0]`, after the binding (appData =
   96 bytes + up to 16 tags; the announce signature covers it).
3. The joiner computes the tag and sends `join {code}` only to nodes
   announcing it. LXMF is end-to-end encrypted, and the sender's npub is
   the one bound in its announce.
4. The inviter checks the code and writes the joiner's `members` row with
   the code's role. It answers `join-ok {b, name, role}` or
   `join-fail {reason}` (invalid, expired, used, self). Normal sync then
   sends the building.
5. After 20 wrong codes, every open code is cancelled.

Limits of a short code: one tag byte narrows who is asked to about
1/256 of nodes, so another node with a colliding open code could see a
joiner's code. A hostile node announcing every tag would receive codes.
The inviter sees who joined, with which npub, and can revoke them.
App versions before 0.3 only accept 96-byte appData, so they ignore a
node's announces while it has an open code.

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
| `need` | `sha: [...]` | Receipts and ID documents referenced but not held. |
| `blob` | `sha, mime, data` | One receipt or ID document (base64). The receiver checks the SHA-256. |
| `skip` | `b, r: [[lane, from, to]…]` | To a tenant: sequences it may not see. Accepted only by a device whose role there is `user`. |
| `join` | `code` | Asks to join with an invite code. |
| `join-ok` / `join-fail` | `b, name, role` / `reason` | The inviter's answer. |

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
- `test/invite_test.dart`: invite codes and roles. A mod joins by code;
  a used or expired code is refused. A mod invites a tenant, who receives
  only their own lease, with no gaps re-asked. Then admin/mod/tenant
  permissions, and a demotion that keeps earlier changes.
- `test/rns_sync_test.dart`: real nodes through a public hub, including
  a join by invite code found through the announce tag:
  `SENHORIO_HUB=rns.wisco.network:4242 flutter test test/rns_sync_test.dart`.
