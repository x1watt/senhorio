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
  },
  'apartments': {
    'name': 'TEXT',
    'floor': 'TEXT',
    'notes': 'TEXT',
  },
  'rooms': {
    'apartment_id': 'TEXT',
    'name': 'TEXT',
    'area_m2': 'REAL',
    'available': 'INTEGER', // 1 = for rent, 0 = kept empty on purpose
    'notes': 'TEXT',
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
    'role': 'TEXT', // owner | member
  },
};

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
];
