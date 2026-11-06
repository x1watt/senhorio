// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Senhorio';

  @override
  String get active => 'Active';

  @override
  String get added => 'Added';

  @override
  String get addMember => 'Add member';

  @override
  String get address => 'Address';

  @override
  String get all => 'All';

  @override
  String get amount => 'Amount';

  @override
  String get apartment => 'Apartment';

  @override
  String get apartmentOptional => 'Apartment (optional)';

  @override
  String get area => 'Area (m²)';

  @override
  String get availableForRent => 'Available for rent';

  @override
  String get backupPassword =>
      'The backup is encrypted. Keep this password with it:';

  @override
  String get backupSaved => 'Backup saved';

  @override
  String get building => 'Building';

  @override
  String get buildings => 'Buildings';

  @override
  String get camera => 'Camera';

  @override
  String get cancel => 'Cancel';

  @override
  String get categories => 'Categories';

  @override
  String get category => 'Category';

  @override
  String get changed => 'Changed';

  @override
  String get checkpoints => 'Checkpoints';

  @override
  String get checkpointsHelp =>
      'Every change is kept in the archive. Open a checkpoint to see what was added, changed or deleted since then, by whom, and to restore it.';

  @override
  String get checkpointsSubtitle =>
      'See and undo what others changed or deleted';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get confirmDelete =>
      'Delete this item? It can be restored from a checkpoint.';

  @override
  String get confirmRestore =>
      'Restore the values from the checkpoint? This change is synced to everyone.';

  @override
  String get confirmRevoke =>
      'Revoke this member? They stop receiving and changing this building.';

  @override
  String get consumption => 'Consumption';

  @override
  String get consumptionUnit => 'Consumption unit';

  @override
  String get copied => 'Copied';

  @override
  String get copyNpub => 'Copy npub';

  @override
  String get currency => 'Currency';

  @override
  String get dashboard => 'Overview';

  @override
  String get date => 'Date';

  @override
  String get delete => 'Delete';

  @override
  String get deleted => 'Deleted';

  @override
  String get deposit => 'Deposit';

  @override
  String get description => 'Description';

  @override
  String get documents => 'Emails & documents';

  @override
  String get dueDay => 'Due day';

  @override
  String get dueDayHint => 'Day of month (weekly: 1 = Monday)';

  @override
  String get edit => 'Edit';

  @override
  String get email => 'Email';

  @override
  String get endDate => 'End date';

  @override
  String get endLeaseToday => 'End lease today';

  @override
  String get everyonePaid => 'Everyone is up to date';

  @override
  String get expectedAmount => 'Expected amount';

  @override
  String get expense => 'Expense';

  @override
  String get expenses => 'Expenses';

  @override
  String get expensesByCategory => 'Expenses by category';

  @override
  String get expensesThisMonth => 'Expenses this month';

  @override
  String get exportBackup => 'Export backup';

  @override
  String get exportBackupHelp => 'The archive with its whole history';

  @override
  String get file => 'File';

  @override
  String get floor => 'Floor';

  @override
  String get frequencyLabel => 'Frequency';

  @override
  String get gallery => 'Gallery';

  @override
  String get graceDays => 'Grace days';

  @override
  String get icon => 'Icon';

  @override
  String get identityHelp =>
      'Your identity is a NOSTR key. Give your npub to the owner of a building so they can add you; keep the nsec secret, it is your signature.';

  @override
  String get identityImported => 'Identity imported';

  @override
  String get importNsec => 'Import an existing nsec';

  @override
  String get importNsecWarning =>
      'This replaces your current identity on this device. Make sure you saved the current nsec.';

  @override
  String get inactive => 'Inactive';

  @override
  String get income => 'Income';

  @override
  String get incomeThisMonth => 'Rent this month';

  @override
  String get incomeVsExpenses => 'Income vs expenses';

  @override
  String get invalidNpub => 'Not a valid npub';

  @override
  String get invalidNsec => 'Not a valid nsec';

  @override
  String get invalidNumber => 'Invalid number';

  @override
  String get keptEmpty => 'Kept empty';

  @override
  String get language => 'Language';

  @override
  String get last12Months => 'Last 12 months';

  @override
  String get lateRent => 'Late rent';

  @override
  String get member => 'Member';

  @override
  String get members => 'Members';

  @override
  String get membersHelpMember =>
      'These people share this building. The owner and admins manage members; mods can invite tenants.';

  @override
  String get membersHelpOwner =>
      'Invite people with a short code, or add their npub. Admins manage everything, mods run the day to day, tenants see only their own lease.';

  @override
  String get method => 'Method';

  @override
  String get methodHint => 'Transfer, cash, MB Way…';

  @override
  String get more => 'More';

  @override
  String get myIdentity => 'My identity';

  @override
  String get name => 'Name';

  @override
  String get net => 'Net';

  @override
  String get newApartment => 'New apartment';

  @override
  String get newBuilding => 'New building';

  @override
  String get newCategory => 'New category';

  @override
  String get newCheckpoint => 'New checkpoint';

  @override
  String get newExpense => 'New expense';

  @override
  String get newLease => 'New lease';

  @override
  String get newRecurringBill => 'New recurring bill';

  @override
  String get newRoom => 'New room';

  @override
  String get newTenant => 'New tenant';

  @override
  String get noApartments => 'No apartments yet. Add one with +.';

  @override
  String get noBuildings => 'No buildings yet.';

  @override
  String get noChanges => 'Nothing changed since this checkpoint';

  @override
  String get noCheckpoints => 'No checkpoints yet';

  @override
  String get noExpenses => 'No expenses yet';

  @override
  String get noRecurringBills =>
      'No recurring bills (water, energy, internet…)';

  @override
  String get noRooms => 'No rooms';

  @override
  String get noTenants => 'No tenants yet';

  @override
  String get notes => 'Notes';

  @override
  String get nothingDue => 'Nothing due in the next two weeks';

  @override
  String get nsecWarning => 'Anyone with your nsec can act as you. Show it?';

  @override
  String get occupancy => 'Occupancy';

  @override
  String get ok => 'OK';

  @override
  String get owner => 'Owner';

  @override
  String get paidOn => 'Paid on';

  @override
  String get pastLeases => 'Past leases';

  @override
  String get payments => 'Payments';

  @override
  String get period => 'Period';

  @override
  String get perRoomMonth => 'per rented room/month';

  @override
  String get phone => 'Phone';

  @override
  String get receipts => 'Receipts';

  @override
  String get recurringBills => 'Recurring bills';

  @override
  String get registerExpense => 'Register';

  @override
  String get registerPayment => 'Register payment';

  @override
  String get rent => 'Rent';

  @override
  String get rentCollected => 'Rent collected';

  @override
  String get required => 'Required';

  @override
  String get restore => 'Restore';

  @override
  String get revoke => 'Revoke';

  @override
  String get roomOptional => 'Room (optional)';

  @override
  String get save => 'Save';

  @override
  String get secretKey => 'Secret key (nsec)';

  @override
  String get since => 'Since';

  @override
  String get startDate => 'Start date';

  @override
  String get statistics => 'Statistics';

  @override
  String get suggested => 'Suggested from your history';

  @override
  String get sync => 'Sync';

  @override
  String get systemLanguage => 'System';

  @override
  String get taxId => 'Tax id (NIF)';

  @override
  String get tenant => 'Tenant';

  @override
  String get tenants => 'Tenants';

  @override
  String get uncategorised => 'Uncategorised';

  @override
  String get undoAdd => 'Remove';

  @override
  String get units => 'Units';

  @override
  String get upcomingBills => 'Bills due soon';

  @override
  String get upToDate => 'Up to date';

  @override
  String get vacant => 'Vacant';

  @override
  String get vanished => 'Removed from the file';

  @override
  String get vendor => 'Vendor';

  @override
  String get waitingForSync => 'Waiting for sync';

  @override
  String get welcome =>
      'Welcome! Start by adding a building in the Buildings tab.';

  @override
  String get wholeApartment => 'Whole apartment';

  @override
  String get wholeBuilding => 'Whole building';

  @override
  String get you => 'You';

  @override
  String changesSince(String label) {
    return 'Since $label';
  }

  @override
  String dueDayN(int day) {
    return 'due day $day';
  }

  @override
  String nextDue(String date) {
    return 'next $date';
  }

  @override
  String paidOf(String paid, String total) {
    return '$paid of $total';
  }

  @override
  String lateAmount(String amount, int count) {
    return '$amount late ($count periods)';
  }

  @override
  String periodsLate(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count periods late',
      one: '1 period late',
    );
    return '$_temp0';
  }

  @override
  String roomsRented(int rented, int total) {
    return '$rented of $total rooms rented';
  }

  @override
  String defaultCategory(String key) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'water': 'Water',
      'energy': 'Electricity',
      'gas': 'Gas',
      'internet': 'Internet',
      'condo': 'Condo fees',
      'material': 'Material',
      'repairs': 'Repairs',
      'cleaning': 'Cleaning',
      'food': 'Food',
      'furniture': 'Furniture',
      'insurance': 'Insurance',
      'taxes': 'Taxes (IMI)',
      'other': 'Other',
    });
    return '$_temp0';
  }

  @override
  String frequency(String f) {
    String _temp0 = intl.Intl.selectLogic(f, {
      'weekly': 'Weekly',
      'monthly': 'Monthly',
      'quarterly': 'Quarterly',
      'yearly': 'Yearly',
      'other': '$f',
    });
    return '$_temp0';
  }

  @override
  String entityName(String t) {
    String _temp0 = intl.Intl.selectLogic(t, {
      'buildings': 'Building',
      'apartments': 'Apartment',
      'rooms': 'Room',
      'tenants': 'Tenant',
      'leases': 'Lease',
      'payments': 'Payment',
      'categories': 'Category',
      'expenses': 'Expense',
      'recurring_bills': 'Recurring bill',
      'documents': 'Document',
      'members': 'Member',
      'other': '$t',
    });
    return '$_temp0';
  }

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncOverReticulum => 'Sync over Reticulum';

  @override
  String get syncHelp =>
      'Encrypted peer-to-peer sync with the members of your buildings, over the internet and the local network.';

  @override
  String get reticulumAddress => 'Reticulum address';

  @override
  String get hubs => 'Hubs';

  @override
  String get hubsHelp => 'One host:port per line';

  @override
  String get noHubConnected => 'No hub connected';

  @override
  String get localNetwork => 'Local network';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get peers => 'Peers seen';

  @override
  String get noPeersYet => 'No peers seen yet';

  @override
  String get activity => 'Activity';

  @override
  String get lastSync => 'Last sync';

  @override
  String syncCounters(
    int sent,
    int received,
    int eventsIn,
    int eventsOut,
    int blobs,
  ) {
    return '$sent sent · $received received · $eventsIn changes in · $eventsOut out · $blobs receipts';
  }

  @override
  String get syncInBackground => 'Keep syncing in the background';

  @override
  String get syncInBackgroundHelp =>
      'Shows a notification while active, so changes arrive with the app closed.';

  @override
  String roomsLate(int n) {
    return '$n late';
  }

  @override
  String roomsOk(int n) {
    return '$n up to date';
  }

  @override
  String roomsEmpty(int n) {
    return '$n empty';
  }

  @override
  String get occupancyHistory => 'Occupancy history';

  @override
  String get today => 'today';

  @override
  String get editTenant => 'Edit tenant';

  @override
  String get idDocuments => 'Identification documents';

  @override
  String get depositHeld => 'Deposit held';

  @override
  String get registerDeposit => 'Register deposit';

  @override
  String get settleDeposit => 'Return / deduct';

  @override
  String get paymentKindLabel => 'Type';

  @override
  String paymentKind(String k) {
    String _temp0 = intl.Intl.selectLogic(k, {
      'rent': 'Rent',
      'deposit': 'Deposit (caução)',
      'provision': 'Provision',
      'deposit_return': 'Deposit returned',
      'deposit_deduction': 'Deposit kept for repairs',
      'other': '$k',
    });
    return '$_temp0';
  }

  @override
  String get periodHint => 'Rent only';

  @override
  String get phone2 => 'Second phone';

  @override
  String get emergencyContact => 'Emergency contact';

  @override
  String get emergencyContactHint => 'Name and phone';

  @override
  String get myOtherDevice => 'My other device';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get installedVersion => 'Installed version';

  @override
  String get upToDateVersion => 'You have the latest version';

  @override
  String updateAvailable(String v) {
    return 'Version $v is available';
  }

  @override
  String get later => 'Later';

  @override
  String get openReleasePage => 'Release page';

  @override
  String get downloadAndInstall => 'Download and install';

  @override
  String get invite => 'Invite';

  @override
  String get joinWithCode => 'Join with a code';

  @override
  String get inviteCode => 'Invite code';

  @override
  String get role => 'Role';

  @override
  String roleName(String role) {
    String _temp0 = intl.Intl.selectLogic(role, {
      'owner': 'Owner',
      'admin': 'Admin',
      'mod': 'Mod',
      'member': 'Mod',
      'user': 'Tenant',
      'other': 'Member',
    });
    return '$_temp0';
  }

  @override
  String roleHelp(String role) {
    String _temp0 = intl.Intl.selectLogic(role, {
      'admin':
          'Co-owner: sees and changes everything, including who is a member.',
      'mod':
          'Runs the day to day: rooms, leases, rents, expenses. Can invite tenants.',
      'user':
          'A tenant: sees only their own lease and payments, changes nothing.',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get whichTenant => 'Which tenant is this person?';

  @override
  String get noTenantsToInvite =>
      'Add the tenant first (Tenants tab), then invite them.';

  @override
  String get nameOptional => 'Name (optional)';

  @override
  String inviteCodeHelp(String time) {
    return 'Give this code to the person. In the app they open Buildings → Join with a code. It works once, until $time.';
  }

  @override
  String get copy => 'Copy';

  @override
  String get openInvites => 'Open invites';

  @override
  String get cancelInvite => 'Cancel invite';

  @override
  String until(String time) {
    return 'until $time';
  }

  @override
  String get enterInviteCode => 'Type the 4-character code you were given.';

  @override
  String get joining => 'Looking for the building…';

  @override
  String joined(String name) {
    return 'You joined $name. Its data is arriving.';
  }

  @override
  String joinError(String reason) {
    String _temp0 = intl.Intl.selectLogic(reason, {
      'invalid': 'This code is not valid.',
      'expired': 'This code has expired: ask for a new one.',
      'used': 'This code was already used.',
      'self': 'That is your own code.',
      'notFound':
          'Nobody is offering this code right now. Check the code, and that the inviter\'s app is open and online.',
      'timeout': 'The inviter did not answer. Try again.',
      'busy': 'Already joining…',
      'other': 'Could not join.',
    });
    return '$_temp0';
  }

  @override
  String get syncNeededForInvites =>
      'Sync is off. Turn it on (More → Sync) to use invite codes.';

  @override
  String get changeRole => 'Change role';

  @override
  String get tenantView =>
      'You are a tenant here: you see your own lease and payments.';
}
