// Tables of the local ZX database.
//
// "Entity" tables are synced: each row is the projection of signed events
// (data/projector.dart) and carries the sync columns below. Nothing is ever
// hard-deleted: a delete sets `deleted = 1`, and ZX keeps every generation.

/// Columns every entity table has, besides its own fields.
const syncColumns = {
  'id': 'TEXT PRIMARY KEY',
  'building_id': 'TEXT',
  'deleted': 'INTEGER DEFAULT 0',
  'updated_hlc': 'TEXT',
  'updated_by': 'TEXT',
  'field_hlc': 'TEXT', // JSON {field: hlc} for field-level last-writer-wins
};

/// Field columns of each synced entity (column -> SQL type).
const entityFields = <String, Map<String, String>>{
  'buildings': {
    'name': 'TEXT',
    'address': 'TEXT',
    'currency': 'TEXT',
    'owner': 'TEXT', // hex pubkey of the creator, immutable
    'notes': 'TEXT',
    'photo': 'TEXT', // sha256 (table attachments) of a presentation picture
  },
  'apartments': {
    'name': 'TEXT',
    'floor': 'TEXT',
    'notes': 'TEXT',
    'photo': 'TEXT',
  },
  'rooms': {
    'apartment_id': 'TEXT',
    'name': 'TEXT',
    'area_m2': 'REAL',
    'available': 'INTEGER', // 1 = for rent, 0 = kept empty on purpose
    'notes': 'TEXT',
    'photo': 'TEXT',
  },
  'tenants': {
    'name': 'TEXT',
    'phone': 'TEXT',
    'phone2': 'TEXT',
    'email': 'TEXT',
    'emergency_contact': 'TEXT', // name and phone of someone to call
    'tax_id': 'TEXT',
    'id_documents': 'TEXT', // JSON list of sha256 (table attachments)
    'notes': 'TEXT',
    // 1 once the managers approved what the tenant entered: from then on
    // only the managers change the row (the tenant cannot erase it).
    'details_locked': 'INTEGER',
  },
  'leases': {
    'room_id': 'TEXT',
    'tenant_id': 'TEXT',
    'rent_cents': 'INTEGER',
    'frequency': 'TEXT', // monthly | weekly | quarterly | yearly
    'due_day': 'INTEGER',
    'start_date': 'TEXT',
    'end_date': 'TEXT',
    'grace_days': 'INTEGER',
    'deposit_cents': 'INTEGER',
    'notes': 'TEXT',
  },
  'payments': {
    'lease_id': 'TEXT',
    // rent | deposit (caução) | provision (provisão) | deposit_return |
    // deposit_deduction (kept for repairs); null = rent
    'kind': 'TEXT',
    'period': 'TEXT', // due date of the period this pays (yyyy-mm-dd)
    'amount_cents': 'INTEGER',
    'paid_on': 'TEXT',
    'method': 'TEXT',
    'notes': 'TEXT',
  },
  'categories': {
    'key': 'TEXT', // default category key, or null for user categories
    'name': 'TEXT',
    'icon': 'TEXT',
    'color': 'INTEGER',
    'unit': 'TEXT', // consumption unit for utilities (kWh, m3, GB)
  },
  'expenses': {
    'apartment_id': 'TEXT',
    'room_id': 'TEXT',
    'category_id': 'TEXT',
    'amount_cents': 'INTEGER',
    'date': 'TEXT',
    'vendor': 'TEXT',
    'description': 'TEXT',
    'quantity': 'REAL',
    'unit': 'TEXT',
    'recurring_bill_id': 'TEXT',
    'shared_bill_id': 'TEXT', // the shared bill this expense is the payment of
    'paid_by': 'TEXT',
    'attachments': 'TEXT', // JSON list of sha256 (table attachments)
  },
  'recurring_bills': {
    'apartment_id': 'TEXT',
    'category_id': 'TEXT',
    'vendor': 'TEXT',
    'description': 'TEXT',
    'expected_cents': 'INTEGER',
    'frequency': 'TEXT',
    'due_day': 'INTEGER',
    'start_date': 'TEXT',
    'active': 'INTEGER',
  },
  // Archived emails / PDFs (structure only for now; import comes later).
  'documents': {
    'kind': 'TEXT', // email | pdf
    'subject': 'TEXT',
    'sender': 'TEXT',
    'date': 'TEXT',
    'raw_sha256': 'TEXT',
    'linked_expense_id': 'TEXT',
  },
  'members': {
    'pubkey': 'TEXT',
    'name': 'TEXT',
    'role': 'TEXT', // owner | admin | mod | user | worker ('member' = mod), see domain/roles.dart
    'tenant_id': 'TEXT', // for role user: the tenant row this person is
  },
  // Global (building ''): what each person says about themselves. The row
  // id is the pubkey and only that pubkey writes it.
  'profiles': {
    'name': 'TEXT',
    'photo': 'TEXT', // sha256 (table attachments)
  },
  // Work (cleaning...) given to a worker, with photo evidence and a review.
  'tasks': {
    'title': 'TEXT',
    'place': 'TEXT', // where, in words: the worker never gets the rows
    'apartment_id': 'TEXT',
    'room_id': 'TEXT',
    'assignee': 'TEXT', // hex pubkey of the worker
    'starts_at': 'TEXT', // ISO 8601 local date-time
    'ends_at': 'TEXT',
    'instructions': 'TEXT',
    'status': 'TEXT', // open | done | approved | rejected
    'photos': 'TEXT', // JSON list of sha256 (table attachments)
    'done_at': 'TEXT',
    'done_note': 'TEXT',
    'reviewed_by': 'TEXT',
    'reviewed_at': 'TEXT',
    'review_note': 'TEXT',
  },
  // A bill a group of tenants shares (the energy of an apartment...),
  // split into one `bill_shares` row per tenant.
  'shared_bills': {
    'title': 'TEXT',
    'apartment_id': 'TEXT', // the group: the apartment's tenants (null: the building's)
    'amount_cents': 'INTEGER',
    'due_date': 'TEXT',
    'description': 'TEXT',
    'attachments': 'TEXT', // JSON list of sha256 (the bill itself)
  },
  'bill_shares': {
    'bill_id': 'TEXT',
    'tenant_id': 'TEXT',
    'amount_cents': 'INTEGER',
    'status': 'TEXT', // open | paid (the tenant says so) | confirmed (by a manager)
    'paid_at': 'TEXT',
    'confirmed_by': 'TEXT',
    'confirmed_at': 'TEXT',
    'note': 'TEXT',
  },
};

/// Columns holding attachment hashes: a JSON list, or one sha256 string.
/// The sync asks peers for the blobs these refer to.
const blobFields = <String, List<String>>{
  'expenses': ['attachments'],
  'tenants': ['id_documents'],
  'tasks': ['photos'],
  'shared_bills': ['attachments'],
  'profiles': ['photo'],
  'buildings': ['photo'],
  'apartments': ['photo'],
  'rooms': ['photo'],
};

/// Fields a tenant may change on their own `tenants` row.
const tenantOwnFields = {'phone', 'phone2', 'email', 'emergency_contact', 'id_documents'};

/// Fields a tenant may change on their own share of a bill (to say it is
/// paid), while a manager has not confirmed it.
const tenantShareFields = {'status', 'paid_at', 'note'};

/// Values of `bill_shares.status`.
const shareStatuses = ['open', 'paid', 'confirmed'];

/// Fields a worker may change on a task assigned to them.
const workerTaskFields = {'status', 'photos', 'done_at', 'done_note'};

/// Values of `tasks.status`.
const taskStatuses = ['open', 'done', 'approved', 'rejected'];

/// Global entities (not tied to a building) use this building id.
const globalBuilding = '';

/// Local tables (not synced as rows).
const localTables = <String, String>{
  // Every signed event, accepted or waiting for its author to be authorised.
  'events': '''CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY, author TEXT, device TEXT, building_id TEXT, seq INTEGER,
    hlc TEXT, entity TEXT, entity_id TEXT, json TEXT,
    status TEXT, received_at INTEGER)''',
  'attachments': '''CREATE TABLE IF NOT EXISTS attachments (
    sha256 TEXT PRIMARY KEY, mime TEXT, size INTEGER, bytes BLOB,
    created_at INTEGER)''',
  'checkpoints': '''CREATE TABLE IF NOT EXISTS checkpoints (
    id TEXT PRIMARY KEY, generation INTEGER, label TEXT, created_by TEXT,
    time INTEGER, auto INTEGER)''',
  'meta': 'CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)',
  // Invite codes made on this device (never synced: the code is the secret).
  'invites': '''CREATE TABLE IF NOT EXISTS invites (
    code TEXT PRIMARY KEY, building_id TEXT, role TEXT, tenant_id TEXT,
    name TEXT, created_at INTEGER, expires_at INTEGER, used_by TEXT,
    used_at INTEGER, cancelled INTEGER DEFAULT 0)''',
  // On a tenant's device: event sequences a manager told us are not for us,
  // so they count as held in our sync vectors.
  'hidden_ranges': '''CREATE TABLE IF NOT EXISTS hidden_ranges (
    building_id TEXT, lane TEXT, from_seq INTEGER, to_seq INTEGER)''',
  // Names this device gives to people (never synced, never shown to them).
  'nicknames': 'CREATE TABLE IF NOT EXISTS nicknames (pubkey TEXT PRIMARY KEY, nickname TEXT)',
};

String createEntityTableSql(String table) {
  final cols = {...syncColumns, ...entityFields[table]!};
  final body = cols.entries.map((e) => '${e.key} ${e.value}').join(', ');
  return 'CREATE TABLE IF NOT EXISTS $table ($body)';
}

/// Columns added to local tables after they were created.
const localTableAdditions = <String, Map<String, String>>{
  'events': {'device': 'TEXT'},
};

const entityIndexes = [
  'CREATE INDEX IF NOT EXISTS events_author ON events (building_id, author, device, seq)',
  'CREATE INDEX IF NOT EXISTS events_status ON events (status)',
  'CREATE INDEX IF NOT EXISTS events_entity ON events (entity, entity_id)',
];
