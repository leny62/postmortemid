import 'package:sqflite/sqflite.dart';

const schemaVersion = 2;

const _schema = [
  '''
  CREATE TABLE animals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    study_code TEXT NOT NULL UNIQUE,
    external_id TEXT,
    linkage_status TEXT NOT NULL,
    created_at TEXT NOT NULL
  )''',
  '''
  CREATE TABLE capture_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    animal_id INTEGER NOT NULL REFERENCES animals(id),
    time_point TEXT NOT NULL,
    modality TEXT NOT NULL,
    purpose TEXT NOT NULL,
    device_model TEXT NOT NULL,
    started_at TEXT NOT NULL
  )''',
  '''
  CREATE TABLE images (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL REFERENCES capture_sessions(id),
    path TEXT NOT NULL,
    quality_passed INTEGER NOT NULL,
    quality_issues TEXT NOT NULL,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    brightness REAL NOT NULL,
    sharpness REAL NOT NULL,
    captured_at TEXT NOT NULL,
    analysed INTEGER NOT NULL DEFAULT 0
  )''',
  '''
  CREATE TABLE templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    animal_id INTEGER NOT NULL REFERENCES animals(id),
    embedding BLOB NOT NULL,
    model_version TEXT NOT NULL,
    image_count INTEGER NOT NULL,
    created_at TEXT NOT NULL
  )''',
  '''
  CREATE TABLE verifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id INTEGER NOT NULL REFERENCES templates(id),
    query_image_id INTEGER NOT NULL REFERENCES images(id),
    similarity REAL NOT NULL,
    tau_far1 REAL NOT NULL,
    tau_far01 REAL NOT NULL,
    decision TEXT NOT NULL,
    model_version TEXT NOT NULL,
    threshold_version TEXT NOT NULL,
    app_version TEXT NOT NULL,
    created_at TEXT NOT NULL
  )''',
];

Future<Database> openStudyDatabase(String path, {DatabaseFactory? factory}) {
  return (factory ?? databaseFactory).openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        for (final statement in _schema) {
          await db.execute(statement);
        }
      },
      onUpgrade: (db, from, _) async {
        // Version 1 wrote image rows only after analysis, so every existing row is analysed.
        if (from < 2) {
          await db.execute('ALTER TABLE images ADD COLUMN analysed INTEGER NOT NULL DEFAULT 1');
        }
      },
    ),
  );
}
