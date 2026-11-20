const fieldConsentKey = 'field_consent_day';

String consentDay(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// Facility permission is given per collection day, so consent lapses at midnight.
bool consentNeeded(String? recordedDay, DateTime now) => recordedDay != consentDay(now);
