import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Senhorio'**
  String get appTitle;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @added.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get added;

  /// No description provided for @addMember.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get addMember;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @apartment.
  ///
  /// In en, this message translates to:
  /// **'Apartment'**
  String get apartment;

  /// No description provided for @apartmentOptional.
  ///
  /// In en, this message translates to:
  /// **'Apartment (optional)'**
  String get apartmentOptional;

  /// No description provided for @area.
  ///
  /// In en, this message translates to:
  /// **'Area (m²)'**
  String get area;

  /// No description provided for @availableForRent.
  ///
  /// In en, this message translates to:
  /// **'Available for rent'**
  String get availableForRent;

  /// No description provided for @backupPassword.
  ///
  /// In en, this message translates to:
  /// **'Restore key: your identity (nsec) and the archive\'s password. Keep it with the backup, e.g. in your password manager. Without it a backup cannot be opened.'**
  String get backupPassword;

  /// No description provided for @backupSaved.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupSaved;

  /// No description provided for @building.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get building;

  /// No description provided for @buildings.
  ///
  /// In en, this message translates to:
  /// **'Buildings'**
  String get buildings;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @changed.
  ///
  /// In en, this message translates to:
  /// **'Changed'**
  String get changed;

  /// No description provided for @checkpoints.
  ///
  /// In en, this message translates to:
  /// **'Checkpoints'**
  String get checkpoints;

  /// No description provided for @checkpointsHelp.
  ///
  /// In en, this message translates to:
  /// **'Every change is kept in the archive. Open a checkpoint to see what was added, changed or deleted since then, by whom, and to restore it.'**
  String get checkpointsHelp;

  /// No description provided for @checkpointsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See and undo what others changed or deleted'**
  String get checkpointsSubtitle;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete this item? It can be restored from a checkpoint.'**
  String get confirmDelete;

  /// No description provided for @confirmRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore the values from the checkpoint? This change is synced to everyone.'**
  String get confirmRestore;

  /// No description provided for @confirmRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke this member? They stop receiving and changing this building.'**
  String get confirmRevoke;

  /// No description provided for @consumption.
  ///
  /// In en, this message translates to:
  /// **'Consumption'**
  String get consumption;

  /// No description provided for @consumptionUnit.
  ///
  /// In en, this message translates to:
  /// **'Consumption unit'**
  String get consumptionUnit;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @copyNpub.
  ///
  /// In en, this message translates to:
  /// **'Copy npub'**
  String get copyNpub;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get dashboard;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// No description provided for @deposit.
  ///
  /// In en, this message translates to:
  /// **'Deposit'**
  String get deposit;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Emails & documents'**
  String get documents;

  /// No description provided for @dueDay.
  ///
  /// In en, this message translates to:
  /// **'Due day'**
  String get dueDay;

  /// No description provided for @dueDayHint.
  ///
  /// In en, this message translates to:
  /// **'Day of month (weekly: 1 = Monday)'**
  String get dueDayHint;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @endDate.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get endDate;

  /// No description provided for @endLeaseToday.
  ///
  /// In en, this message translates to:
  /// **'End lease today'**
  String get endLeaseToday;

  /// No description provided for @everyonePaid.
  ///
  /// In en, this message translates to:
  /// **'Everyone is up to date'**
  String get everyonePaid;

  /// No description provided for @expectedAmount.
  ///
  /// In en, this message translates to:
  /// **'Expected amount'**
  String get expectedAmount;

  /// No description provided for @expense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expense;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @expensesByCategory.
  ///
  /// In en, this message translates to:
  /// **'Expenses by category'**
  String get expensesByCategory;

  /// No description provided for @expensesThisMonth.
  ///
  /// In en, this message translates to:
  /// **'Expenses this month'**
  String get expensesThisMonth;

  /// No description provided for @exportBackup.
  ///
  /// In en, this message translates to:
  /// **'Export backup'**
  String get exportBackup;

  /// No description provided for @exportBackupHelp.
  ///
  /// In en, this message translates to:
  /// **'The whole archive, to a file that survives uninstalling the app'**
  String get exportBackupHelp;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @floor.
  ///
  /// In en, this message translates to:
  /// **'Floor'**
  String get floor;

  /// No description provided for @frequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get frequencyLabel;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @graceDays.
  ///
  /// In en, this message translates to:
  /// **'Grace days'**
  String get graceDays;

  /// No description provided for @icon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get icon;

  /// No description provided for @identityHelp.
  ///
  /// In en, this message translates to:
  /// **'Your identity is a NOSTR key. Give your npub to the owner of a building so they can add you; keep the nsec secret, it is your signature.'**
  String get identityHelp;

  /// No description provided for @identityImported.
  ///
  /// In en, this message translates to:
  /// **'Identity imported'**
  String get identityImported;

  /// No description provided for @importNsec.
  ///
  /// In en, this message translates to:
  /// **'Import an existing nsec'**
  String get importNsec;

  /// No description provided for @importNsecWarning.
  ///
  /// In en, this message translates to:
  /// **'This replaces your current identity on this device. Make sure you saved the current nsec.'**
  String get importNsecWarning;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @income.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get income;

  /// No description provided for @incomeThisMonth.
  ///
  /// In en, this message translates to:
  /// **'Rent this month'**
  String get incomeThisMonth;

  /// No description provided for @incomeVsExpenses.
  ///
  /// In en, this message translates to:
  /// **'Income vs expenses'**
  String get incomeVsExpenses;

  /// No description provided for @invalidNpub.
  ///
  /// In en, this message translates to:
  /// **'Not a valid npub'**
  String get invalidNpub;

  /// No description provided for @invalidNsec.
  ///
  /// In en, this message translates to:
  /// **'Not a valid nsec'**
  String get invalidNsec;

  /// No description provided for @invalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Invalid number'**
  String get invalidNumber;

  /// No description provided for @keptEmpty.
  ///
  /// In en, this message translates to:
  /// **'Kept empty'**
  String get keptEmpty;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @last12Months.
  ///
  /// In en, this message translates to:
  /// **'Last 12 months'**
  String get last12Months;

  /// No description provided for @lateRent.
  ///
  /// In en, this message translates to:
  /// **'Late rent'**
  String get lateRent;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @membersHelpMember.
  ///
  /// In en, this message translates to:
  /// **'These people share this building. The owner and admins manage members; mods can invite tenants.'**
  String get membersHelpMember;

  /// No description provided for @membersHelpOwner.
  ///
  /// In en, this message translates to:
  /// **'Invite people with a short code, or add their npub. Admins manage everything, mods run the day to day, tenants see only their own lease.'**
  String get membersHelpOwner;

  /// No description provided for @method.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get method;

  /// No description provided for @methodHint.
  ///
  /// In en, this message translates to:
  /// **'Transfer, cash, MB Way…'**
  String get methodHint;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @myIdentity.
  ///
  /// In en, this message translates to:
  /// **'My identity'**
  String get myIdentity;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @net.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get net;

  /// No description provided for @newApartment.
  ///
  /// In en, this message translates to:
  /// **'New apartment'**
  String get newApartment;

  /// No description provided for @newBuilding.
  ///
  /// In en, this message translates to:
  /// **'New building'**
  String get newBuilding;

  /// No description provided for @newCategory.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get newCategory;

  /// No description provided for @newCheckpoint.
  ///
  /// In en, this message translates to:
  /// **'New checkpoint'**
  String get newCheckpoint;

  /// No description provided for @newExpense.
  ///
  /// In en, this message translates to:
  /// **'New expense'**
  String get newExpense;

  /// No description provided for @newLease.
  ///
  /// In en, this message translates to:
  /// **'New lease'**
  String get newLease;

  /// No description provided for @newRecurringBill.
  ///
  /// In en, this message translates to:
  /// **'New recurring bill'**
  String get newRecurringBill;

  /// No description provided for @newRoom.
  ///
  /// In en, this message translates to:
  /// **'New room'**
  String get newRoom;

  /// No description provided for @newTenant.
  ///
  /// In en, this message translates to:
  /// **'New tenant'**
  String get newTenant;

  /// No description provided for @noApartments.
  ///
  /// In en, this message translates to:
  /// **'No apartments yet. Add one with +.'**
  String get noApartments;

  /// No description provided for @noBuildings.
  ///
  /// In en, this message translates to:
  /// **'No buildings yet.'**
  String get noBuildings;

  /// No description provided for @noChanges.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed since this checkpoint'**
  String get noChanges;

  /// No description provided for @noCheckpoints.
  ///
  /// In en, this message translates to:
  /// **'No checkpoints yet'**
  String get noCheckpoints;

  /// No description provided for @noExpenses.
  ///
  /// In en, this message translates to:
  /// **'No expenses yet'**
  String get noExpenses;

  /// No description provided for @noRecurringBills.
  ///
  /// In en, this message translates to:
  /// **'No recurring bills (water, energy, internet…)'**
  String get noRecurringBills;

  /// No description provided for @noRooms.
  ///
  /// In en, this message translates to:
  /// **'No rooms'**
  String get noRooms;

  /// No description provided for @noTenants.
  ///
  /// In en, this message translates to:
  /// **'No tenants yet'**
  String get noTenants;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @nothingDue.
  ///
  /// In en, this message translates to:
  /// **'Nothing due in the next two weeks'**
  String get nothingDue;

  /// No description provided for @nsecWarning.
  ///
  /// In en, this message translates to:
  /// **'Anyone with your nsec can act as you. Show it?'**
  String get nsecWarning;

  /// No description provided for @occupancy.
  ///
  /// In en, this message translates to:
  /// **'Occupancy'**
  String get occupancy;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// No description provided for @paidOn.
  ///
  /// In en, this message translates to:
  /// **'Paid on'**
  String get paidOn;

  /// No description provided for @pastLeases.
  ///
  /// In en, this message translates to:
  /// **'Past leases'**
  String get pastLeases;

  /// No description provided for @payments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get payments;

  /// No description provided for @period.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get period;

  /// No description provided for @perRoomMonth.
  ///
  /// In en, this message translates to:
  /// **'per rented room/month'**
  String get perRoomMonth;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @receipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get receipts;

  /// No description provided for @recurringBills.
  ///
  /// In en, this message translates to:
  /// **'Recurring bills'**
  String get recurringBills;

  /// No description provided for @registerExpense.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get registerExpense;

  /// No description provided for @registerPayment.
  ///
  /// In en, this message translates to:
  /// **'Register payment'**
  String get registerPayment;

  /// No description provided for @rent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get rent;

  /// No description provided for @rentCollected.
  ///
  /// In en, this message translates to:
  /// **'Rent collected'**
  String get rentCollected;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @roomOptional.
  ///
  /// In en, this message translates to:
  /// **'Room (optional)'**
  String get roomOptional;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @secretKey.
  ///
  /// In en, this message translates to:
  /// **'Secret key (nsec)'**
  String get secretKey;

  /// No description provided for @since.
  ///
  /// In en, this message translates to:
  /// **'Since'**
  String get since;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get startDate;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @suggested.
  ///
  /// In en, this message translates to:
  /// **'Suggested from your history'**
  String get suggested;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @systemLanguage.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemLanguage;

  /// No description provided for @taxId.
  ///
  /// In en, this message translates to:
  /// **'Tax id (NIF)'**
  String get taxId;

  /// No description provided for @tenant.
  ///
  /// In en, this message translates to:
  /// **'Tenant'**
  String get tenant;

  /// No description provided for @tenants.
  ///
  /// In en, this message translates to:
  /// **'Tenants'**
  String get tenants;

  /// No description provided for @uncategorised.
  ///
  /// In en, this message translates to:
  /// **'Uncategorised'**
  String get uncategorised;

  /// No description provided for @undoAdd.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get undoAdd;

  /// No description provided for @units.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get units;

  /// No description provided for @upcomingBills.
  ///
  /// In en, this message translates to:
  /// **'Bills due soon'**
  String get upcomingBills;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get upToDate;

  /// No description provided for @vacant.
  ///
  /// In en, this message translates to:
  /// **'Vacant'**
  String get vacant;

  /// No description provided for @vanished.
  ///
  /// In en, this message translates to:
  /// **'Removed from the file'**
  String get vanished;

  /// No description provided for @vendor.
  ///
  /// In en, this message translates to:
  /// **'Vendor'**
  String get vendor;

  /// No description provided for @waitingForSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting for sync'**
  String get waitingForSync;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome! Start by adding a building in the Buildings tab.'**
  String get welcome;

  /// No description provided for @wholeApartment.
  ///
  /// In en, this message translates to:
  /// **'Whole apartment'**
  String get wholeApartment;

  /// No description provided for @wholeBuilding.
  ///
  /// In en, this message translates to:
  /// **'Whole building'**
  String get wholeBuilding;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @changesSince.
  ///
  /// In en, this message translates to:
  /// **'Since {label}'**
  String changesSince(String label);

  /// No description provided for @dueDayN.
  ///
  /// In en, this message translates to:
  /// **'due day {day}'**
  String dueDayN(int day);

  /// No description provided for @nextDue.
  ///
  /// In en, this message translates to:
  /// **'next {date}'**
  String nextDue(String date);

  /// No description provided for @paidOf.
  ///
  /// In en, this message translates to:
  /// **'{paid} of {total}'**
  String paidOf(String paid, String total);

  /// No description provided for @lateAmount.
  ///
  /// In en, this message translates to:
  /// **'{amount} late ({count} periods)'**
  String lateAmount(String amount, int count);

  /// No description provided for @periodsLate.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 period late} other{{count} periods late}}'**
  String periodsLate(num count);

  /// No description provided for @roomsRented.
  ///
  /// In en, this message translates to:
  /// **'{rented} of {total} rooms rented'**
  String roomsRented(int rented, int total);

  /// No description provided for @defaultCategory.
  ///
  /// In en, this message translates to:
  /// **'{key, select, water{Water} energy{Electricity} gas{Gas} internet{Internet} condo{Condo fees} material{Material} repairs{Repairs} cleaning{Cleaning} food{Food} furniture{Furniture} insurance{Insurance} taxes{Taxes (IMI)} other{Other}}'**
  String defaultCategory(String key);

  /// No description provided for @frequency.
  ///
  /// In en, this message translates to:
  /// **'{f, select, weekly{Weekly} monthly{Monthly} quarterly{Quarterly} yearly{Yearly} other{{f}}}'**
  String frequency(String f);

  /// No description provided for @entityName.
  ///
  /// In en, this message translates to:
  /// **'{t, select, buildings{Building} apartments{Apartment} rooms{Room} tenants{Tenant} leases{Lease} payments{Payment} categories{Category} expenses{Expense} recurring_bills{Recurring bill} documents{Document} members{Member} other{{t}}}'**
  String entityName(String t);

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncOverReticulum.
  ///
  /// In en, this message translates to:
  /// **'Sync over Reticulum'**
  String get syncOverReticulum;

  /// No description provided for @syncHelp.
  ///
  /// In en, this message translates to:
  /// **'Encrypted peer-to-peer sync with the members of your buildings, over the internet and the local network.'**
  String get syncHelp;

  /// No description provided for @reticulumAddress.
  ///
  /// In en, this message translates to:
  /// **'Reticulum address'**
  String get reticulumAddress;

  /// No description provided for @hubs.
  ///
  /// In en, this message translates to:
  /// **'Hubs'**
  String get hubs;

  /// No description provided for @hubsHelp.
  ///
  /// In en, this message translates to:
  /// **'One host:port per line'**
  String get hubsHelp;

  /// No description provided for @noHubConnected.
  ///
  /// In en, this message translates to:
  /// **'No hub connected'**
  String get noHubConnected;

  /// No description provided for @localNetwork.
  ///
  /// In en, this message translates to:
  /// **'Local network'**
  String get localNetwork;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @peers.
  ///
  /// In en, this message translates to:
  /// **'Peers seen'**
  String get peers;

  /// No description provided for @noPeersYet.
  ///
  /// In en, this message translates to:
  /// **'No peers seen yet'**
  String get noPeersYet;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @lastSync.
  ///
  /// In en, this message translates to:
  /// **'Last sync'**
  String get lastSync;

  /// No description provided for @syncCounters.
  ///
  /// In en, this message translates to:
  /// **'{sent} sent · {received} received · {eventsIn} changes in · {eventsOut} out · {blobs} receipts'**
  String syncCounters(
    int sent,
    int received,
    int eventsIn,
    int eventsOut,
    int blobs,
  );

  /// No description provided for @syncInBackground.
  ///
  /// In en, this message translates to:
  /// **'Keep syncing in the background'**
  String get syncInBackground;

  /// No description provided for @syncInBackgroundHelp.
  ///
  /// In en, this message translates to:
  /// **'Shows a notification while active, so changes arrive with the app closed.'**
  String get syncInBackgroundHelp;

  /// No description provided for @roomsLate.
  ///
  /// In en, this message translates to:
  /// **'{n} late'**
  String roomsLate(int n);

  /// No description provided for @roomsOk.
  ///
  /// In en, this message translates to:
  /// **'{n} up to date'**
  String roomsOk(int n);

  /// No description provided for @roomsEmpty.
  ///
  /// In en, this message translates to:
  /// **'{n} empty'**
  String roomsEmpty(int n);

  /// No description provided for @occupancyHistory.
  ///
  /// In en, this message translates to:
  /// **'Occupancy history'**
  String get occupancyHistory;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get today;

  /// No description provided for @editTenant.
  ///
  /// In en, this message translates to:
  /// **'Edit tenant'**
  String get editTenant;

  /// No description provided for @idDocuments.
  ///
  /// In en, this message translates to:
  /// **'Identification documents'**
  String get idDocuments;

  /// No description provided for @depositHeld.
  ///
  /// In en, this message translates to:
  /// **'Deposit held'**
  String get depositHeld;

  /// No description provided for @registerDeposit.
  ///
  /// In en, this message translates to:
  /// **'Register deposit'**
  String get registerDeposit;

  /// No description provided for @settleDeposit.
  ///
  /// In en, this message translates to:
  /// **'Return / deduct'**
  String get settleDeposit;

  /// No description provided for @paymentKindLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get paymentKindLabel;

  /// No description provided for @paymentKind.
  ///
  /// In en, this message translates to:
  /// **'{k, select, rent{Rent} deposit{Deposit (caução)} provision{Provision} deposit_return{Deposit returned} deposit_deduction{Deposit kept for repairs} other{{k}}}'**
  String paymentKind(String k);

  /// No description provided for @periodHint.
  ///
  /// In en, this message translates to:
  /// **'Rent only'**
  String get periodHint;

  /// No description provided for @phone2.
  ///
  /// In en, this message translates to:
  /// **'Second phone'**
  String get phone2;

  /// No description provided for @emergencyContact.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact'**
  String get emergencyContact;

  /// No description provided for @emergencyContactHint.
  ///
  /// In en, this message translates to:
  /// **'Name and phone'**
  String get emergencyContactHint;

  /// No description provided for @myOtherDevice.
  ///
  /// In en, this message translates to:
  /// **'My other device'**
  String get myOtherDevice;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @installedVersion.
  ///
  /// In en, this message translates to:
  /// **'Installed version'**
  String get installedVersion;

  /// No description provided for @upToDateVersion.
  ///
  /// In en, this message translates to:
  /// **'You have the latest version'**
  String get upToDateVersion;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {v} is available'**
  String updateAvailable(String v);

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @openReleasePage.
  ///
  /// In en, this message translates to:
  /// **'Release page'**
  String get openReleasePage;

  /// No description provided for @downloadAndInstall.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get downloadAndInstall;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @joinWithCode.
  ///
  /// In en, this message translates to:
  /// **'Join with a code'**
  String get joinWithCode;

  /// No description provided for @inviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCode;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @roleName.
  ///
  /// In en, this message translates to:
  /// **'{role, select, owner{Owner} admin{Admin} mod{Mod} member{Mod} user{Tenant} other{Member}}'**
  String roleName(String role);

  /// No description provided for @roleHelp.
  ///
  /// In en, this message translates to:
  /// **'{role, select, admin{Co-owner: sees and changes everything, including who is a member.} mod{Runs the day to day: rooms, leases, rents, expenses. Can invite tenants.} user{A tenant: sees only their own lease and payments, changes nothing.} other{}}'**
  String roleHelp(String role);

  /// No description provided for @whichTenant.
  ///
  /// In en, this message translates to:
  /// **'Which tenant is this person?'**
  String get whichTenant;

  /// No description provided for @noTenantsToInvite.
  ///
  /// In en, this message translates to:
  /// **'Add the tenant first (Tenants tab), then invite them.'**
  String get noTenantsToInvite;

  /// No description provided for @nameOptional.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get nameOptional;

  /// No description provided for @inviteCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'Give this code to the person. In the app they open Buildings → Join with a code. It works once, until {time}.'**
  String inviteCodeHelp(String time);

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @openInvites.
  ///
  /// In en, this message translates to:
  /// **'Open invites'**
  String get openInvites;

  /// No description provided for @cancelInvite.
  ///
  /// In en, this message translates to:
  /// **'Cancel invite'**
  String get cancelInvite;

  /// No description provided for @until.
  ///
  /// In en, this message translates to:
  /// **'until {time}'**
  String until(String time);

  /// No description provided for @enterInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Type the 4-character code you were given.'**
  String get enterInviteCode;

  /// No description provided for @joining.
  ///
  /// In en, this message translates to:
  /// **'Looking for the building…'**
  String get joining;

  /// No description provided for @joined.
  ///
  /// In en, this message translates to:
  /// **'You joined {name}. Its data is arriving.'**
  String joined(String name);

  /// No description provided for @joinError.
  ///
  /// In en, this message translates to:
  /// **'{reason, select, invalid{This code is not valid.} expired{This code has expired: ask for a new one.} used{This code was already used.} self{That is your own code.} notFound{Nobody is offering this code right now. Check the code, and that the inviter\'s app is open and online.} timeout{The inviter did not answer. Try again.} busy{Already joining…} other{Could not join.}}'**
  String joinError(String reason);

  /// No description provided for @syncNeededForInvites.
  ///
  /// In en, this message translates to:
  /// **'Sync is off. Turn it on (More → Sync) to use invite codes.'**
  String get syncNeededForInvites;

  /// No description provided for @changeRole.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get changeRole;

  /// No description provided for @tenantView.
  ///
  /// In en, this message translates to:
  /// **'You are a tenant here: you see your own lease and payments.'**
  String get tenantView;

  /// No description provided for @copyRestoreKey.
  ///
  /// In en, this message translates to:
  /// **'Copy restore key'**
  String get copyRestoreKey;

  /// No description provided for @restoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get restoreBackup;

  /// No description provided for @restoreBackupHelp.
  ///
  /// In en, this message translates to:
  /// **'Replace this device\'s data with a backup file'**
  String get restoreBackupHelp;

  /// No description provided for @restoreKey.
  ///
  /// In en, this message translates to:
  /// **'Restore key'**
  String get restoreKey;

  /// No description provided for @restoreKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Paste the restore key shown when the backup was made (the nsec and the password).'**
  String get restoreKeyHelp;

  /// No description provided for @restoreKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'The restore key needs the nsec and the 64-character password.'**
  String get restoreKeyInvalid;

  /// No description provided for @restoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replace everything on this device with {file}? The current data is kept as senhorio-before-restore.zx in the app\'s folder.'**
  String restoreConfirm(String file);

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not restore: wrong password, or not a Senhorio backup.'**
  String get restoreFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
