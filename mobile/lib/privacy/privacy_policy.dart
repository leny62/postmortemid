import 'policy_provision.dart';

const privacyPolicyVersion = 'Version 1, 20 November 2026';
const ethicsContact = 'researchethics@alueducation.com';

const privacyProvisions = [
  PolicyProvision(
    title: 'What this app is',
    promise:
        'A research prototype from an African Leadership University capstone study '
        '(ethics approval SEPT26-BSE-022). It tests whether a cow\'s muzzle photographed '
        'alive still matches the same cow after slaughter. It is not an insurance, '
        'registry or veterinary tool.',
    keptBy:
        'The home screen shows the prototype status and the model and threshold versions. '
        'Every stored result records those versions.',
  ),
  PolicyProvision(
    title: 'What is collected',
    promise:
        'Photos of cattle muzzles and faces, a study code for each animal (for example '
        'PM-A01), photo times, the phone model, and the field log: slaughter time, head '
        'washed, nose condition, link certainty and notes.',
    keptBy:
        'The database has no field for an owner\'s name, phone number, ID number or '
        'location, so the app cannot store them.',
  ),
  PolicyProvision(
    title: 'What never leaves this phone',
    promise:
        'The ear tag number. It can lead to the owner through the national registry, so '
        'it is treated as personal data.',
    keptBy:
        'Exports and uploads build each animal\'s log from the study code only; the ear '
        'tag field is left out of the CSV export, the field zip and the upload.',
  ),
  PolicyProvision(
    title: 'Where data is kept',
    promise:
        'In the app\'s private storage on this phone. Matching runs on the phone and '
        'works without internet.',
    keptBy:
        'The model and thresholds ship inside the app. The only network call is the '
        'field photo upload, and it runs only when you press Upload.',
  ),
  PolicyProvision(
    title: 'What is shared and with whom',
    promise:
        'Field photos and animal logs go to the study server over HTTPS when you upload '
        'them. Only the researcher can download them.',
    keptBy:
        'Uploading needs a personal collector key. Downloading needs a separate admin key '
        'that collectors do not have.',
  ),
  PolicyProvision(
    title: 'Who decides',
    promise:
        'The app answers Match, Review or No match. Review means a person decides. No '
        'result from this prototype may be used to approve or refuse a claim.',
    keptBy:
        'Scores between the two thresholds return Review. The thresholds were fixed on '
        'development animals, not on the animals being checked.',
  ),
  PolicyProvision(
    title: 'Consent',
    promise:
        'Collectors confirm each collection day that they agree to take part and that '
        'the facility has given permission. People, documents and screens are not '
        'photographed, and names are not written in notes.',
    keptBy:
        'Adding an animal asks for this confirmation once per day and keeps the date on '
        'this phone.',
  ),
  PolicyProvision(
    title: 'Your choices',
    promise:
        'You can stop at any time. Uninstalling the app deletes everything it stored on '
        'this phone. To remove uploaded photos, ask the researcher or write to '
        '$ethicsContact.',
    keptBy:
        'All app data lives in the app\'s own storage, which the phone removes on '
        'uninstall.',
  ),
];

const privacyLimits = [
  'Uploaded photos are deleted by the researcher on request; the server does not delete '
      'them on its own yet.',
  'The ear tag is kept in the app database on this phone, not in a separate encrypted file.',
  'Photos keep the camera\'s own metadata, such as the time they were taken.',
  'The model was tested on live cattle only. Its accuracy after death is not known yet.',
];

const fieldConsentStatements = [
  'I have read the field brief and agree to collect photos for this study. I can stop at '
      'any time.',
  'The facility manager has given permission for today\'s collection.',
  'I will photograph animals only: no people, documents or screens, and no names in the '
      'notes.',
];
