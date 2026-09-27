/// File-backed database for native platforms (dart:io).
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'src/database.dart';

/// Opens `<directory>/hermuse.sqlite` on a background isolate.
HermuseDatabase openNativeDatabase(Directory directory) => HermuseDatabase(
  NativeDatabase.createInBackground(File('${directory.path}/hermuse.sqlite')),
);

/// In-memory database (tests).
///
/// Query streams close synchronously: drift otherwise parks a zero-duration
/// [Timer] on unsubscribe, which fails widget tests ("a Timer is still
/// pending even after the widget tree was disposed").
HermuseDatabase openMemoryDatabase() => HermuseDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);
