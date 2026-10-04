import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
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
    Locale('te'),
  ];

  /// Collector interface: Continue
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// Collector interface: Sign out
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// Collector interface: Study ID
  ///
  /// In en, this message translates to:
  /// **'Study ID'**
  String get studyId;

  /// Collector interface: Participant name
  ///
  /// In en, this message translates to:
  /// **'Participant name'**
  String get participantName;

  /// Collector interface: Phone number
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// Collector interface: Save and continue
  ///
  /// In en, this message translates to:
  /// **'Save and continue'**
  String get saveAndContinue;

  /// Collector interface: Review and submit
  ///
  /// In en, this message translates to:
  /// **'Review and submit'**
  String get reviewAndSubmit;

  /// Collector interface: Back
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Collector interface: Submission receipt
  ///
  /// In en, this message translates to:
  /// **'Submission receipt'**
  String get submissionReceipt;

  /// Collector interface: Optional Step 2
  ///
  /// In en, this message translates to:
  /// **'Optional Step 2'**
  String get optionalStep2;

  /// Collector interface: New participant
  ///
  /// In en, this message translates to:
  /// **'New participant'**
  String get newParticipant;

  /// Collector interface: Retry pending sync
  ///
  /// In en, this message translates to:
  /// **'Retry pending sync'**
  String get retryPendingSync;

  /// Collector interface: Start a visit or return to one of your saved submissions.
  ///
  /// In en, this message translates to:
  /// **'Start a visit or return to one of your saved submissions.'**
  String get startAVisitOrReturnToOneOfYourSavedSubmissions;

  /// Collector interface: Some saved visits need attention
  ///
  /// In en, this message translates to:
  /// **'Some saved visits need attention'**
  String get someSavedVisitsNeedAttention;

  /// Collector interface: Awaiting sync
  ///
  /// In en, this message translates to:
  /// **'Awaiting sync'**
  String get awaitingSync;

  /// Collector interface: Recent submissions
  ///
  /// In en, this message translates to:
  /// **'Recent submissions'**
  String get recentSubmissions;

  /// Collector interface: In-progress visit saved
  ///
  /// In en, this message translates to:
  /// **'In-progress visit saved'**
  String get inProgressVisitSaved;

  /// Collector interface: Continue where you left off.
  ///
  /// In en, this message translates to:
  /// **'Continue where you left off.'**
  String get continueWhereYouLeftOff;

  /// Collector interface: Recent activity
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivity;

  /// Collector interface: View all
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// Collector interface: No submissions yet
  ///
  /// In en, this message translates to:
  /// **'No submissions yet'**
  String get noSubmissionsYet;

  /// Collector interface: Your completed and saved visits will appear here.
  ///
  /// In en, this message translates to:
  /// **'Your completed and saved visits will appear here.'**
  String get yourCompletedAndSavedVisitsWillAppearHere;

  /// Collector interface: Saved on this device
  ///
  /// In en, this message translates to:
  /// **'Saved on this device'**
  String get savedOnThisDevice;

  /// Collector interface: Synced
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get synced;

  /// Collector interface: Pending sync
  ///
  /// In en, this message translates to:
  /// **'Pending sync'**
  String get pendingSync;

  /// Collector interface: Sync needs attention
  ///
  /// In en, this message translates to:
  /// **'Sync needs attention'**
  String get syncNeedsAttention;

  /// Collector interface: Optional information can be added only when appropriate.
  ///
  /// In en, this message translates to:
  /// **'Optional information can be added only when appropriate.'**
  String get optionalInformationCanBeAddedOnlyWhenAppropriate;

  /// Collector interface: Optional note
  ///
  /// In en, this message translates to:
  /// **'Optional note'**
  String get optionalNote;

  /// Collector interface: Leave blank to continue without this step.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to continue without this step.'**
  String get leaveBlankToContinueWithoutThisStep;

  /// Collector interface: Skip this optional step
  ///
  /// In en, this message translates to:
  /// **'Skip this optional step'**
  String get skipThisOptionalStep;

  /// Collector interface: Participant
  ///
  /// In en, this message translates to:
  /// **'Participant'**
  String get participant;

  /// Collector interface: Find a participant or start a new participant record.
  ///
  /// In en, this message translates to:
  /// **'Find a participant or start a new participant record.'**
  String get findAParticipantOrStartANewParticipantRecord;

  /// Collector interface: Repeat visit using Study ID
  ///
  /// In en, this message translates to:
  /// **'Repeat visit using Study ID'**
  String get repeatVisitUsingStudyId;

  /// Collector interface: Find by name and phone
  ///
  /// In en, this message translates to:
  /// **'Find by name and phone'**
  String get findByNameAndPhone;

  /// Collector interface: Looks up saved visits on this phone, so it works without internet. Use the Study ID printed on the participant’s card or logbook.
  ///
  /// In en, this message translates to:
  /// **'Looks up saved visits on this phone, so it works without internet. Use the Study ID printed on the participant’s card or logbook.'**
  String
  get looksUpSavedVisitsOnThisPhoneSoItWorksWithoutInternetUseTheStudyIdPrintedOnTheParticipantSCardOrLogbook;

  /// Collector interface: Study ID from card/logbook
  ///
  /// In en, this message translates to:
  /// **'Study ID from card/logbook'**
  String get studyIdFromCardLogbook;

  /// Collector interface: Enter a valid Study ID, such as C07-000123.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Study ID, such as C07-000123.'**
  String get enterAValidStudyIdSuchAsC07000123;

  /// Collector interface: Enter a participant name.
  ///
  /// In en, this message translates to:
  /// **'Enter a participant name.'**
  String get enterAParticipantName;

  /// Collector interface: Enter a phone number.
  ///
  /// In en, this message translates to:
  /// **'Enter a phone number.'**
  String get enterAPhoneNumber;

  /// Collector interface: Find saved participant
  ///
  /// In en, this message translates to:
  /// **'Find saved participant'**
  String get findSavedParticipant;

  /// Collector interface: Find participant
  ///
  /// In en, this message translates to:
  /// **'Find participant'**
  String get findParticipant;

  /// Collector interface: Confirm visit
  ///
  /// In en, this message translates to:
  /// **'Confirm visit'**
  String get confirmVisit;

  /// Collector interface: Check the automatically assigned participant and visit numbers.
  ///
  /// In en, this message translates to:
  /// **'Check the automatically assigned participant and visit numbers.'**
  String get checkTheAutomaticallyAssignedParticipantAndVisitNumbers;

  /// Collector interface: Participant number
  ///
  /// In en, this message translates to:
  /// **'Participant number'**
  String get participantNumber;

  /// Collector interface: First visit
  ///
  /// In en, this message translates to:
  /// **'First visit'**
  String get firstVisit;

  /// Collector interface: A new participant number has been assigned.
  ///
  /// In en, this message translates to:
  /// **'A new participant number has been assigned.'**
  String get aNewParticipantNumberHasBeenAssigned;

  /// Collector interface: Updated automatically from this participant’s history.
  ///
  /// In en, this message translates to:
  /// **'Updated automatically from this participant’s history.'**
  String get updatedAutomaticallyFromThisParticipantSHistory;

  /// Collector interface: Confirm and continue
  ///
  /// In en, this message translates to:
  /// **'Confirm and continue'**
  String get confirmAndContinue;

  /// Collector interface: My submissions
  ///
  /// In en, this message translates to:
  /// **'My submissions'**
  String get mySubmissions;

  /// Collector interface: Entries created by your account.
  ///
  /// In en, this message translates to:
  /// **'Entries created by your account.'**
  String get entriesCreatedByYourAccount;

  /// Collector interface: Search by name or Study ID
  ///
  /// In en, this message translates to:
  /// **'Search by name or Study ID'**
  String get searchByNameOrStudyId;

  /// Collector interface: No matching submissions
  ///
  /// In en, this message translates to:
  /// **'No matching submissions'**
  String get noMatchingSubmissions;

  /// Collector interface: Try a different search or create a new participant entry.
  ///
  /// In en, this message translates to:
  /// **'Try a different search or create a new participant entry.'**
  String get tryADifferentSearchOrCreateANewParticipantEntry;

  /// Collector interface: Edit
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Collector interface: Edit submission
  ///
  /// In en, this message translates to:
  /// **'Edit submission'**
  String get editSubmission;

  /// Collector interface: Submission details
  ///
  /// In en, this message translates to:
  /// **'Submission details'**
  String get submissionDetails;

  /// Collector interface: Submission ID
  ///
  /// In en, this message translates to:
  /// **'Submission ID'**
  String get submissionId;

  /// Collector interface: Recorded
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get recorded;

  /// Collector interface: Sync status
  ///
  /// In en, this message translates to:
  /// **'Sync status'**
  String get syncStatus;

  /// Collector interface: Review submission
  ///
  /// In en, this message translates to:
  /// **'Review submission'**
  String get reviewSubmission;

  /// Collector interface: Check every answer before submitting.
  ///
  /// In en, this message translates to:
  /// **'Check every answer before submitting.'**
  String get checkEveryAnswerBeforeSubmitting;

  /// Collector interface: Name
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// Collector interface: Phone
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// Collector interface: Study and profile
  ///
  /// In en, this message translates to:
  /// **'Study and profile'**
  String get studyAndProfile;

  /// Collector interface: Visit number
  ///
  /// In en, this message translates to:
  /// **'Visit number'**
  String get visitNumber;

  /// Collector interface: Study site
  ///
  /// In en, this message translates to:
  /// **'Study site'**
  String get studySite;

  /// Collector interface: Age
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get age;

  /// Collector interface: Sex
  ///
  /// In en, this message translates to:
  /// **'Sex'**
  String get sex;

  /// Collector interface: Education level
  ///
  /// In en, this message translates to:
  /// **'Education level'**
  String get educationLevel;

  /// Collector interface: Work category
  ///
  /// In en, this message translates to:
  /// **'Work category'**
  String get workCategory;

  /// Collector interface: Tobacco and alcohol
  ///
  /// In en, this message translates to:
  /// **'Tobacco and alcohol'**
  String get tobaccoAndAlcohol;

  /// Collector interface: Tobacco use
  ///
  /// In en, this message translates to:
  /// **'Tobacco use'**
  String get tobaccoUse;

  /// Collector interface: Tobacco type
  ///
  /// In en, this message translates to:
  /// **'Tobacco type'**
  String get tobaccoType;

  /// Collector interface: Tobacco frequency
  ///
  /// In en, this message translates to:
  /// **'Tobacco frequency'**
  String get tobaccoFrequency;

  /// Collector interface: Alcohol in past 30 days
  ///
  /// In en, this message translates to:
  /// **'Alcohol in past 30 days'**
  String get alcoholInPast30Days;

  /// Collector interface: Alcohol frequency
  ///
  /// In en, this message translates to:
  /// **'Alcohol frequency'**
  String get alcoholFrequency;

  /// Collector interface: Diet, activity and sleep
  ///
  /// In en, this message translates to:
  /// **'Diet, activity and sleep'**
  String get dietActivityAndSleep;

  /// Collector interface: Fruit (past 7 days)
  ///
  /// In en, this message translates to:
  /// **'Fruit (past 7 days)'**
  String get fruitPast7Days;

  /// Collector interface: Vegetables (past 7 days)
  ///
  /// In en, this message translates to:
  /// **'Vegetables (past 7 days)'**
  String get vegetablesPast7Days;

  /// Collector interface: Sugary drinks (past 7 days)
  ///
  /// In en, this message translates to:
  /// **'Sugary drinks (past 7 days)'**
  String get sugaryDrinksPast7Days;

  /// Collector interface: Processed foods (past 7 days)
  ///
  /// In en, this message translates to:
  /// **'Processed foods (past 7 days)'**
  String get processedFoodsPast7Days;

  /// Collector interface: Active days per week
  ///
  /// In en, this message translates to:
  /// **'Active days per week'**
  String get activeDaysPerWeek;

  /// Collector interface: Active minutes per day
  ///
  /// In en, this message translates to:
  /// **'Active minutes per day'**
  String get activeMinutesPerDay;

  /// Collector interface: Weekly active minutes
  ///
  /// In en, this message translates to:
  /// **'Weekly active minutes'**
  String get weeklyActiveMinutes;

  /// Collector interface: Sleep per night
  ///
  /// In en, this message translates to:
  /// **'Sleep per night'**
  String get sleepPerNight;

  /// Collector interface: Known diagnoses
  ///
  /// In en, this message translates to:
  /// **'Known diagnoses'**
  String get knownDiagnoses;

  /// Collector interface: Hypertension
  ///
  /// In en, this message translates to:
  /// **'Hypertension'**
  String get hypertension;

  /// Collector interface: Diabetes
  ///
  /// In en, this message translates to:
  /// **'Diabetes'**
  String get diabetes;

  /// Collector interface: High cholesterol
  ///
  /// In en, this message translates to:
  /// **'High cholesterol'**
  String get highCholesterol;

  /// Collector interface: Cardiovascular disease
  ///
  /// In en, this message translates to:
  /// **'Cardiovascular disease'**
  String get cardiovascularDisease;

  /// Collector interface: Physical measurements
  ///
  /// In en, this message translates to:
  /// **'Physical measurements'**
  String get physicalMeasurements;

  /// Collector interface: Height
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get height;

  /// Collector interface: Weight
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get weight;

  /// Collector interface: Waist circumference
  ///
  /// In en, this message translates to:
  /// **'Waist circumference'**
  String get waistCircumference;

  /// Collector interface: Hip circumference
  ///
  /// In en, this message translates to:
  /// **'Hip circumference'**
  String get hipCircumference;

  /// Collector interface: Waist-to-hip ratio
  ///
  /// In en, this message translates to:
  /// **'Waist-to-hip ratio'**
  String get waistToHipRatio;

  /// Collector interface: BMI
  ///
  /// In en, this message translates to:
  /// **'BMI'**
  String get bmi;

  /// Collector interface: Blood pressure reading 1
  ///
  /// In en, this message translates to:
  /// **'Blood pressure reading 1'**
  String get bloodPressureReading1;

  /// Collector interface: Blood pressure reading 2
  ///
  /// In en, this message translates to:
  /// **'Blood pressure reading 2'**
  String get bloodPressureReading2;

  /// Collector interface: Average blood pressure
  ///
  /// In en, this message translates to:
  /// **'Average blood pressure'**
  String get averageBloodPressure;

  /// Collector interface: Saving...
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// Collector interface: Not completed
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get notCompleted;

  /// Collector interface: Not answered
  ///
  /// In en, this message translates to:
  /// **'Not answered'**
  String get notAnswered;

  /// Collector interface: Not applicable
  ///
  /// In en, this message translates to:
  /// **'Not applicable'**
  String get notApplicable;

  /// Collector interface: Not recorded
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get notRecorded;

  /// Collector interface: Not calculated
  ///
  /// In en, this message translates to:
  /// **'Not calculated'**
  String get notCalculated;

  /// Collector interface: Not collected
  ///
  /// In en, this message translates to:
  /// **'Not collected'**
  String get notCollected;

  /// Collector interface: Not provided
  ///
  /// In en, this message translates to:
  /// **'Not provided'**
  String get notProvided;

  /// Collector interface: Community clinic
  ///
  /// In en, this message translates to:
  /// **'Community clinic'**
  String get communityClinic;

  /// Collector interface: Community outreach
  ///
  /// In en, this message translates to:
  /// **'Community outreach'**
  String get communityOutreach;

  /// Collector interface: Other study site
  ///
  /// In en, this message translates to:
  /// **'Other study site'**
  String get otherStudySite;

  /// Collector interface: Female
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get female;

  /// Collector interface: Male
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get male;

  /// Collector interface: Other
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// Collector interface: No formal schooling
  ///
  /// In en, this message translates to:
  /// **'No formal schooling'**
  String get noFormalSchooling;

  /// Collector interface: Primary
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get primary;

  /// Collector interface: Secondary
  ///
  /// In en, this message translates to:
  /// **'Secondary'**
  String get secondary;

  /// Collector interface: Higher education
  ///
  /// In en, this message translates to:
  /// **'Higher education'**
  String get higherEducation;

  /// Collector interface: Employed
  ///
  /// In en, this message translates to:
  /// **'Employed'**
  String get employed;

  /// Collector interface: Self-employed
  ///
  /// In en, this message translates to:
  /// **'Self-employed'**
  String get selfEmployed;

  /// Collector interface: Student
  ///
  /// In en, this message translates to:
  /// **'Student'**
  String get student;

  /// Collector interface: Homemaker/care work
  ///
  /// In en, this message translates to:
  /// **'Homemaker/care work'**
  String get homemakerCareWork;

  /// Collector interface: Not currently employed
  ///
  /// In en, this message translates to:
  /// **'Not currently employed'**
  String get notCurrentlyEmployed;

  /// Collector interface: Retired
  ///
  /// In en, this message translates to:
  /// **'Retired'**
  String get retired;

  /// Collector interface: Never used
  ///
  /// In en, this message translates to:
  /// **'Never used'**
  String get neverUsed;

  /// Collector interface: Former user
  ///
  /// In en, this message translates to:
  /// **'Former user'**
  String get formerUser;

  /// Collector interface: Current user
  ///
  /// In en, this message translates to:
  /// **'Current user'**
  String get currentUser;

  /// Collector interface: Smoked
  ///
  /// In en, this message translates to:
  /// **'Smoked'**
  String get smoked;

  /// Collector interface: Smokeless
  ///
  /// In en, this message translates to:
  /// **'Smokeless'**
  String get smokeless;

  /// Collector interface: Both
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get both;

  /// Collector interface: Daily
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get daily;

  /// Collector interface: Less than daily
  ///
  /// In en, this message translates to:
  /// **'Less than daily'**
  String get lessThanDaily;

  /// Collector interface: Less than weekly
  ///
  /// In en, this message translates to:
  /// **'Less than weekly'**
  String get lessThanWeekly;

  /// Collector interface: 1–3 days/week
  ///
  /// In en, this message translates to:
  /// **'1–3 days/week'**
  String get frequency13DaysWeek;

  /// Collector interface: 4+ days/week
  ///
  /// In en, this message translates to:
  /// **'4+ days/week'**
  String get frequency4DaysWeek;

  /// Collector interface: Never
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// Collector interface: 1–2 days
  ///
  /// In en, this message translates to:
  /// **'1–2 days'**
  String get frequency12Days;

  /// Collector interface: 3–4 days
  ///
  /// In en, this message translates to:
  /// **'3–4 days'**
  String get frequency34Days;

  /// Collector interface: 5–6 days
  ///
  /// In en, this message translates to:
  /// **'5–6 days'**
  String get frequency56Days;

  /// Collector interface: Every day
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get everyDay;

  /// Collector interface: Yes
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// Collector interface: No
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// Collector interface: Don’t know
  ///
  /// In en, this message translates to:
  /// **'Don’t know'**
  String get donTKnow;

  /// Collector interface: Declined
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get declined;

  /// Collector interface: Unable to measure
  ///
  /// In en, this message translates to:
  /// **'Unable to measure'**
  String get unableToMeasure;

  /// Collector interface: NCD risk questionnaire
  ///
  /// In en, this message translates to:
  /// **'NCD risk questionnaire'**
  String get ncdRiskQuestionnaire;

  /// Collector interface: Interview questions · 1 of 2. Leave sensitive answers blank if the participant declines.
  ///
  /// In en, this message translates to:
  /// **'Interview questions · 1 of 2. Leave sensitive answers blank if the participant declines.'**
  String
  get interviewQuestions1Of2LeaveSensitiveAnswersBlankIfTheParticipantDeclines;

  /// Collector interface: Age (years)
  ///
  /// In en, this message translates to:
  /// **'Age (years)'**
  String get ageYears;

  /// Collector interface: Employment/work category
  ///
  /// In en, this message translates to:
  /// **'Employment/work category'**
  String get employmentWorkCategory;

  /// Collector interface: Type of tobacco
  ///
  /// In en, this message translates to:
  /// **'Type of tobacco'**
  String get typeOfTobacco;

  /// Collector interface: Alcohol use in the past 30 days
  ///
  /// In en, this message translates to:
  /// **'Alcohol use in the past 30 days'**
  String get alcoholUseInThePast30Days;

  /// Collector interface: In the past 7 days, how often did the participant have:
  ///
  /// In en, this message translates to:
  /// **'In the past 7 days, how often did the participant have:'**
  String get inThePast7DaysHowOftenDidTheParticipantHave;

  /// Collector interface: Fruit
  ///
  /// In en, this message translates to:
  /// **'Fruit'**
  String get fruit;

  /// Collector interface: Vegetables
  ///
  /// In en, this message translates to:
  /// **'Vegetables'**
  String get vegetables;

  /// Collector interface: Sugary drinks
  ///
  /// In en, this message translates to:
  /// **'Sugary drinks'**
  String get sugaryDrinks;

  /// Collector interface: Processed or packaged foods
  ///
  /// In en, this message translates to:
  /// **'Processed or packaged foods'**
  String get processedOrPackagedFoods;

  /// Collector interface: Moderate-or-higher activity
  ///
  /// In en, this message translates to:
  /// **'Moderate-or-higher activity'**
  String get moderateOrHigherActivity;

  /// Collector interface: Usual active minutes per day
  ///
  /// In en, this message translates to:
  /// **'Usual active minutes per day'**
  String get usualActiveMinutesPerDay;

  /// Collector interface: Usual sleep hours per night
  ///
  /// In en, this message translates to:
  /// **'Usual sleep hours per night'**
  String get usualSleepHoursPerNight;

  /// Collector interface: Known diagnosis
  ///
  /// In en, this message translates to:
  /// **'Known diagnosis'**
  String get knownDiagnosis;

  /// Collector interface: Has a doctor or health professional ever told the participant they have:
  ///
  /// In en, this message translates to:
  /// **'Has a doctor or health professional ever told the participant they have:'**
  String get hasADoctorOrHealthProfessionalEverToldTheParticipantTheyHave;

  /// Collector interface: Continue to measurements
  ///
  /// In en, this message translates to:
  /// **'Continue to measurements'**
  String get continueToMeasurements;

  /// Collector interface: Measurements · 2 of 2. Record both blood-pressure readings.
  ///
  /// In en, this message translates to:
  /// **'Measurements · 2 of 2. Record both blood-pressure readings.'**
  String get measurements2Of2RecordBothBloodPressureReadings;

  /// Collector interface: Body measurements
  ///
  /// In en, this message translates to:
  /// **'Body measurements'**
  String get bodyMeasurements;

  /// Collector interface: Height (cm)
  ///
  /// In en, this message translates to:
  /// **'Height (cm)'**
  String get heightCm;

  /// Collector interface: Weight (kg)
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get weightKg;

  /// Collector interface: Waist circumference (cm)
  ///
  /// In en, this message translates to:
  /// **'Waist circumference (cm)'**
  String get waistCircumferenceCm;

  /// Collector interface: Hip circumference (cm)
  ///
  /// In en, this message translates to:
  /// **'Hip circumference (cm)'**
  String get hipCircumferenceCm;

  /// Collector interface: Blood pressure
  ///
  /// In en, this message translates to:
  /// **'Blood pressure'**
  String get bloodPressure;

  /// Collector interface: Record two seated readings in mmHg.
  ///
  /// In en, this message translates to:
  /// **'Record two seated readings in mmHg.'**
  String get recordTwoSeatedReadingsInMmhg;

  /// Collector interface: Reading 1
  ///
  /// In en, this message translates to:
  /// **'Reading 1'**
  String get reading1;

  /// Collector interface: Reading 2
  ///
  /// In en, this message translates to:
  /// **'Reading 2'**
  String get reading2;

  /// Collector interface: Review questionnaire
  ///
  /// In en, this message translates to:
  /// **'Review questionnaire'**
  String get reviewQuestionnaire;

  /// Collector interface: Measured
  ///
  /// In en, this message translates to:
  /// **'Measured'**
  String get measured;

  /// Collector interface: Select an answer.
  ///
  /// In en, this message translates to:
  /// **'Select an answer.'**
  String get selectAnAnswer;

  /// Collector interface: Optional — leave blank if declined.
  ///
  /// In en, this message translates to:
  /// **'Optional — leave blank if declined.'**
  String get optionalLeaveBlankIfDeclined;

  /// Collector interface: Systolic must be greater than diastolic.
  ///
  /// In en, this message translates to:
  /// **'Systolic must be greater than diastolic.'**
  String get systolicMustBeGreaterThanDiastolic;

  /// Collector interface: Enter a value.
  ///
  /// In en, this message translates to:
  /// **'Enter a value.'**
  String get enterAValue;

  /// Collector interface: Return home
  ///
  /// In en, this message translates to:
  /// **'Return home'**
  String get returnHome;

  /// Collector interface: View submission
  ///
  /// In en, this message translates to:
  /// **'View submission'**
  String get viewSubmission;

  /// Collector interface: This entry remains safely stored on this device and will sync when available.
  ///
  /// In en, this message translates to:
  /// **'This entry remains safely stored on this device and will sync when available.'**
  String get thisEntryRemainsSafelyStoredOnThisDeviceAndWillSyncWhenAvailable;

  /// Collector interface: Sign-in is not configured. Contact your administrator.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is not configured. Contact your administrator.'**
  String get signInIsNotConfiguredContactYourAdministrator;

  /// Collector interface: The QR code is invalid. Ask your administrator for a new one.
  ///
  /// In en, this message translates to:
  /// **'The QR code is invalid. Ask your administrator for a new one.'**
  String get theQrCodeIsInvalidAskYourAdministratorForANewOne;

  /// Collector interface: QR sign-in was cancelled. Scan your setup QR code to continue.
  ///
  /// In en, this message translates to:
  /// **'QR sign-in was cancelled. Scan your setup QR code to continue.'**
  String get qrSignInWasCancelledScanYourSetupQrCodeToContinue;

  /// Collector interface: Camera access is needed to scan your setup QR code. Allow camera access in app settings.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed to scan your setup QR code. Allow camera access in app settings.'**
  String
  get cameraAccessIsNeededToScanYourSetupQrCodeAllowCameraAccessInAppSettings;

  /// Collector interface: The camera is unavailable. Check camera access and try again.
  ///
  /// In en, this message translates to:
  /// **'The camera is unavailable. Check camera access and try again.'**
  String get theCameraIsUnavailableCheckCameraAccessAndTryAgain;

  /// Collector interface: Scan the collector setup QR code provided by your administrator to sign in.
  ///
  /// In en, this message translates to:
  /// **'Scan the collector setup QR code provided by your administrator to sign in.'**
  String get scanTheCollectorSetupQrCodeProvidedByYourAdministratorToSignIn;

  /// Collector interface: Enter your collector number and access details. Before switching phones, sync any pending visits on the old phone. Signing in here ends its session for this number.
  ///
  /// In en, this message translates to:
  /// **'Enter your collector number and access details. Before switching phones, sync any pending visits on the old phone. Signing in here ends its session for this number.'**
  String
  get enterYourCollectorNumberAndAccessDetailsBeforeSwitchingPhonesSyncAnyPendingVisitsOnTheOldPhoneSigningInHereEndsItsSessionForThisNumber;

  /// Collector interface: Enter the collector number created by the administrator. The first phone to use it becomes the assigned phone.
  ///
  /// In en, this message translates to:
  /// **'Enter the collector number created by the administrator. The first phone to use it becomes the assigned phone.'**
  String
  get enterTheCollectorNumberCreatedByTheAdministratorTheFirstPhoneToUseItBecomesTheAssignedPhone;

  /// Collector interface: Collector number
  ///
  /// In en, this message translates to:
  /// **'Collector number'**
  String get collectorNumber;

  /// Collector interface: Enter a number such as 1.
  ///
  /// In en, this message translates to:
  /// **'Enter a number such as 1.'**
  String get enterANumberSuchAs1;

  /// Collector interface: Server address
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddress;

  /// Collector interface: Home server address
  ///
  /// In en, this message translates to:
  /// **'Home server address'**
  String get homeServerAddress;

  /// Collector interface: Enter the server address provided by the administrator.
  ///
  /// In en, this message translates to:
  /// **'Enter the server address provided by the administrator.'**
  String get enterTheServerAddressProvidedByTheAdministrator;

  /// Collector interface: Collector access key
  ///
  /// In en, this message translates to:
  /// **'Collector access key'**
  String get collectorAccessKey;

  /// Collector interface: Enter your collector access key.
  ///
  /// In en, this message translates to:
  /// **'Enter your collector access key.'**
  String get enterYourCollectorAccessKey;

  /// Collector interface: Scanning…
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get scanning;

  /// Collector interface: Scan sign-in QR
  ///
  /// In en, this message translates to:
  /// **'Scan sign-in QR'**
  String get scanSignInQr;

  /// Collector interface: Scan collector setup code
  ///
  /// In en, this message translates to:
  /// **'Scan collector setup code'**
  String get scanCollectorSetupCode;

  /// Collector interface: Cancel scan
  ///
  /// In en, this message translates to:
  /// **'Cancel scan'**
  String get cancelScan;

  /// Collector interface: The camera is unavailable. Please try again.
  ///
  /// In en, this message translates to:
  /// **'The camera is unavailable. Please try again.'**
  String get theCameraIsUnavailablePleaseTryAgain;

  /// Collector interface: This QR code could not be validated as a collector setup code.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be validated as a collector setup code.'**
  String get thisQrCodeCouldNotBeValidatedAsACollectorSetupCode;

  /// Collector interface: Camera access is needed to scan a setup code. Allow camera access in your device settings, then try again.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed to scan a setup code. Allow camera access in your device settings, then try again.'**
  String
  get cameraAccessIsNeededToScanASetupCodeAllowCameraAccessInYourDeviceSettingsThenTryAgain;

  /// Collector interface: Try again
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// Collector interface: Close scanner
  ///
  /// In en, this message translates to:
  /// **'Close scanner'**
  String get closeScanner;

  /// Collector interface: Scan again
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get scanAgain;

  /// Collector interface: Place the collector setup QR code inside the frame.
  ///
  /// In en, this message translates to:
  /// **'Place the collector setup QR code inside the frame.'**
  String get placeTheCollectorSetupQrCodeInsideTheFrame;

  /// Collector interface: Collector number must be positive.
  ///
  /// In en, this message translates to:
  /// **'Collector number must be positive.'**
  String get collectorNumberMustBePositive;

  /// Collector interface: Collector number not found.
  ///
  /// In en, this message translates to:
  /// **'Collector number not found.'**
  String get collectorNumberNotFound;

  /// Collector interface: This collector number is disabled.
  ///
  /// In en, this message translates to:
  /// **'This collector number is disabled.'**
  String get thisCollectorNumberIsDisabled;

  /// Collector interface: This collector number is assigned to another phone.
  ///
  /// In en, this message translates to:
  /// **'This collector number is assigned to another phone.'**
  String get thisCollectorNumberIsAssignedToAnotherPhone;

  /// Collector interface: Collector access could not be verified. Try again.
  ///
  /// In en, this message translates to:
  /// **'Collector access could not be verified. Try again.'**
  String get collectorAccessCouldNotBeVerifiedTryAgain;

  /// Collector interface: Could not connect. Check the internet and try again.
  ///
  /// In en, this message translates to:
  /// **'Could not connect. Check the internet and try again.'**
  String get couldNotConnectCheckTheInternetAndTryAgain;

  /// Collector interface: Saved submissions could not be opened
  ///
  /// In en, this message translates to:
  /// **'Saved submissions could not be opened'**
  String get savedSubmissionsCouldNotBeOpened;

  /// Collector interface: The app has not discarded or replaced the saved data.
  ///
  /// In en, this message translates to:
  /// **'The app has not discarded or replaced the saved data.'**
  String get theAppHasNotDiscardedOrReplacedTheSavedData;

  /// Collector interface: LOCAL DEMO · enter your assigned collector number
  ///
  /// In en, this message translates to:
  /// **'LOCAL DEMO · enter your assigned collector number'**
  String get localDemoEnterYourAssignedCollectorNumber;

  /// Collector interface: Some saved visit drafts could not be restored. Other saved visits are still available.
  ///
  /// In en, this message translates to:
  /// **'Some saved visit drafts could not be restored. Other saved visits are still available.'**
  String
  get someSavedVisitDraftsCouldNotBeRestoredOtherSavedVisitsAreStillAvailable;

  /// Collector interface: Enter a valid Indian mobile number.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Indian mobile number.'**
  String get enterAValidIndianMobileNumber;

  /// Collector interface: Could not reserve the visit. Check the internet and try again.
  ///
  /// In en, this message translates to:
  /// **'Could not reserve the visit. Check the internet and try again.'**
  String get couldNotReserveTheVisitCheckTheInternetAndTryAgain;

  /// Collector interface: This collector number signed in on another phone. Sign in again here to take over.
  ///
  /// In en, this message translates to:
  /// **'This collector number signed in on another phone. Sign in again here to take over.'**
  String get thisCollectorNumberSignedInOnAnotherPhoneSignInAgainHereToTakeOver;

  /// Collector interface: Details do not match
  ///
  /// In en, this message translates to:
  /// **'Details do not match'**
  String get detailsDoNotMatch;

  /// Collector interface: This Study ID already has a different name or phone number. Please confirm the details with the participant.
  ///
  /// In en, this message translates to:
  /// **'This Study ID already has a different name or phone number. Please confirm the details with the participant.'**
  String
  get thisStudyIdAlreadyHasADifferentNameOrPhoneNumberPleaseConfirmTheDetailsWithTheParticipant;

  /// Collector interface: Go back
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// Collector interface: Details confirmed
  ///
  /// In en, this message translates to:
  /// **'Details confirmed'**
  String get detailsConfirmed;

  /// Collector interface: No saved visit for this Study ID is available on this phone. Connect to the study archive or sync the phone that has its history.
  ///
  /// In en, this message translates to:
  /// **'No saved visit for this Study ID is available on this phone. Connect to the study archive or sync the phone that has its history.'**
  String
  get noSavedVisitForThisStudyIdIsAvailableOnThisPhoneConnectToTheStudyArchiveOrSyncThePhoneThatHasItsHistory;

  /// Collector interface: Saved details for this Study ID do not agree. Check the study card and contact the supervisor before continuing.
  ///
  /// In en, this message translates to:
  /// **'Saved details for this Study ID do not agree. Check the study card and contact the supervisor before continuing.'**
  String
  get savedDetailsForThisStudyIdDoNotAgreeCheckTheStudyCardAndContactTheSupervisorBeforeContinuing;

  /// Collector interface: Visit already in progress
  ///
  /// In en, this message translates to:
  /// **'Visit already in progress'**
  String get visitAlreadyInProgress;

  /// Collector interface: Cancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Collector interface: Resume visit
  ///
  /// In en, this message translates to:
  /// **'Resume visit'**
  String get resumeVisit;

  /// Collector interface: Could not save an in-progress copy on this phone. The visit was not opened.
  ///
  /// In en, this message translates to:
  /// **'Could not save an in-progress copy on this phone. The visit was not opened.'**
  String get couldNotSaveAnInProgressCopyOnThisPhoneTheVisitWasNotOpened;

  /// Collector interface: Could not save recent answers on this phone. Check storage before continuing.
  ///
  /// In en, this message translates to:
  /// **'Could not save recent answers on this phone. Check storage before continuing.'**
  String get couldNotSaveRecentAnswersOnThisPhoneCheckStorageBeforeContinuing;

  /// Collector interface: Resume a saved visit
  ///
  /// In en, this message translates to:
  /// **'Resume a saved visit'**
  String get resumeASavedVisit;

  /// Collector interface: Choose participant
  ///
  /// In en, this message translates to:
  /// **'Choose participant'**
  String get chooseParticipant;

  /// Collector interface: This phone number may be shared. Check the participant’s name and Study ID before continuing.
  ///
  /// In en, this message translates to:
  /// **'This phone number may be shared. Check the participant’s name and Study ID before continuing.'**
  String
  get thisPhoneNumberMayBeSharedCheckTheParticipantSNameAndStudyIdBeforeContinuing;

  /// Collector interface: Record synced successfully.
  ///
  /// In en, this message translates to:
  /// **'Record synced successfully.'**
  String get recordSyncedSuccessfully;

  /// Collector interface: Sync conflict: entry is saved on this phone and needs admin review.
  ///
  /// In en, this message translates to:
  /// **'Sync conflict: entry is saved on this phone and needs admin review.'**
  String get syncConflictEntryIsSavedOnThisPhoneAndNeedsAdminReview;

  /// Collector interface: Could not save on this phone. Entry was not sent. Try again.
  ///
  /// In en, this message translates to:
  /// **'Could not save on this phone. Entry was not sent. Try again.'**
  String get couldNotSaveOnThisPhoneEntryWasNotSentTryAgain;

  /// Collector interface: Sync Conflict - Review Required
  ///
  /// In en, this message translates to:
  /// **'Sync Conflict - Review Required'**
  String get syncConflictReviewRequired;

  /// Collector interface: Specify Study ID from card/logbook
  ///
  /// In en, this message translates to:
  /// **'Specify Study ID from card/logbook'**
  String get specifyStudyIdFromCardLogbook;

  /// Collector interface: If this participant was enrolled on another collector's phone, please specify the exact Study ID from their card or logbook.
  ///
  /// In en, this message translates to:
  /// **'If this participant was enrolled on another collector\'s phone, please specify the exact Study ID from their card or logbook.'**
  String
  get ifThisParticipantWasEnrolledOnAnotherCollectorSPhonePleaseSpecifyTheExactStudyIdFromTheirCardOrLogbook;

  /// Collector interface: Invalid Study ID format. Must be like C01-000001 or P001.
  ///
  /// In en, this message translates to:
  /// **'Invalid Study ID format. Must be like C01-000001 or P001.'**
  String get invalidStudyIdFormatMustBeLikeC01000001OrP001;

  /// Collector interface: Visit number must be an integer of 2 or greater.
  ///
  /// In en, this message translates to:
  /// **'Visit number must be an integer of 2 or greater.'**
  String get visitNumberMustBeAnIntegerOf2OrGreater;

  /// Collector interface: Confirm Study ID
  ///
  /// In en, this message translates to:
  /// **'Confirm Study ID'**
  String get confirmStudyId;

  /// Collector interface: Specify existing Study ID (from card/logbook)
  ///
  /// In en, this message translates to:
  /// **'Specify existing Study ID (from card/logbook)'**
  String get specifyExistingStudyIdFromCardLogbook;

  /// Collector interface: Conflict Review
  ///
  /// In en, this message translates to:
  /// **'Conflict Review'**
  String get conflictReview;

  /// Collector interface: A conflict (HTTP 409) occurred while uploading this submission to the study server.
  ///
  /// In en, this message translates to:
  /// **'A conflict (HTTP 409) occurred while uploading this submission to the study server.'**
  String
  get aConflictHttp409OccurredWhileUploadingThisSubmissionToTheStudyServer;

  /// Collector interface: The entry remains safely stored locally on this phone. You can manually retry uploading once server-side conflicts are addressed.
  ///
  /// In en, this message translates to:
  /// **'The entry remains safely stored locally on this phone. You can manually retry uploading once server-side conflicts are addressed.'**
  String
  get theEntryRemainsSafelyStoredLocallyOnThisPhoneYouCanManuallyRetryUploadingOnceServerSideConflictsAreAddressed;

  /// Collector interface: Close
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Collector interface: Retry Upload
  ///
  /// In en, this message translates to:
  /// **'Retry Upload'**
  String get retryUpload;

  /// Collector interface: Editing submitted entries is not available in this demo.
  ///
  /// In en, this message translates to:
  /// **'Editing submitted entries is not available in this demo.'**
  String get editingSubmittedEntriesIsNotAvailableInThisDemo;

  /// Collector interface: Review Conflict
  ///
  /// In en, this message translates to:
  /// **'Review Conflict'**
  String get reviewConflict;

  /// Collector interface: Conflict Ref
  ///
  /// In en, this message translates to:
  /// **'Conflict Ref'**
  String get conflictRef;

  /// Collector interface: Sign-in failed. Check your setup code and connection, then try again.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Check your setup code and connection, then try again.'**
  String get signInFailedCheckYourSetupCodeAndConnectionThenTryAgain;

  /// Collector interface: Your entry is saved on this phone. Contact the administrator to resolve the sync conflict, then retry uploading.
  ///
  /// In en, this message translates to:
  /// **'Your entry is saved on this phone. Contact the administrator to resolve the sync conflict, then retry uploading.'**
  String
  get yourEntryIsSavedOnThisPhoneContactTheAdministratorToResolveTheSyncConflictThenRetryUploading;

  /// Collector interface: Hello, {name}
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String hello(String name);

  /// Collector interface: Collector {number}
  ///
  /// In en, this message translates to:
  /// **'Collector {number}'**
  String collector(String number);

  /// Collector interface: {number} in-progress visits saved
  ///
  /// In en, this message translates to:
  /// **'{number} in-progress visits saved'**
  String inProgressVisitsSaved(String number);

  /// Collector interface: {id} · Visit {number}
  ///
  /// In en, this message translates to:
  /// **'{id} · Visit {number}'**
  String visit(String id, String number);

  /// Collector interface: Visit {number}
  ///
  /// In en, this message translates to:
  /// **'Visit {number}'**
  String visit2(String number);

  /// Collector interface: Next visit {number}
  ///
  /// In en, this message translates to:
  /// **'Next visit {number}'**
  String nextVisit(String number);

  /// Collector interface: Visit {number} for {name} is saved.
  ///
  /// In en, this message translates to:
  /// **'Visit {number} for {name} is saved.'**
  String visitForIsSaved(String number, String name);

  /// Collector interface: {name} has an unfinished Visit {number}. Resume it before starting another visit.
  ///
  /// In en, this message translates to:
  /// **'{name} has an unfinished Visit {number}. Resume it before starting another visit.'**
  String hasAnUnfinishedVisitResumeItBeforeStartingAnotherVisit(
    String name,
    String number,
  );

  /// Collector interface: This phone is locked to Collector {number}. You cannot switch collector accounts.
  ///
  /// In en, this message translates to:
  /// **'This phone is locked to Collector {number}. You cannot switch collector accounts.'**
  String thisPhoneIsLockedToCollectorYouCannotSwitchCollectorAccounts(
    String number,
  );

  /// Collector interface: {label} status
  ///
  /// In en, this message translates to:
  /// **'{label} status'**
  String status(String label);

  /// Collector interface: {label} systolic
  ///
  /// In en, this message translates to:
  /// **'{label} systolic'**
  String systolic(String label);

  /// Collector interface: {label} diastolic
  ///
  /// In en, this message translates to:
  /// **'{label} diastolic'**
  String diastolic(String label);

  /// Collector interface: Enter a value from {min} to {max}.
  ///
  /// In en, this message translates to:
  /// **'Enter a value from {min} to {max}.'**
  String enterAValueFromTo(String min, String max);

  /// Collector interface: {number} years
  ///
  /// In en, this message translates to:
  /// **'{number} years'**
  String years(String number);

  /// Collector interface: {number} hours
  ///
  /// In en, this message translates to:
  /// **'{number} hours'**
  String hours(String number);

  /// Collector interface: {number} min/week
  ///
  /// In en, this message translates to:
  /// **'{number} min/week'**
  String minWeek(String number);

  /// Collector interface: Submission ID: {id}
  ///
  /// In en, this message translates to:
  /// **'Submission ID: {id}'**
  String submissionId2(String id);

  /// Collector interface: Conflict Reference: {id}
  ///
  /// In en, this message translates to:
  /// **'Conflict Reference: {id}'**
  String conflictReference(String id);

  /// Collector interface: Conflict Details: {details}
  ///
  /// In en, this message translates to:
  /// **'Conflict Details: {details}'**
  String conflictDetails(String details);

  /// Collector interface: Participant: {name} ({id})
  ///
  /// In en, this message translates to:
  /// **'Participant: {name} ({id})'**
  String participant2(String name, String id);

  /// Collector interface: Visit: {number}
  ///
  /// In en, this message translates to:
  /// **'Visit: {number}'**
  String visit3(String number);

  /// Collector interface: Recorded: {time}
  ///
  /// In en, this message translates to:
  /// **'Recorded: {time}'**
  String recorded2(String time);
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
      <String>['en', 'te'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'te':
      return AppLocalizationsTe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
