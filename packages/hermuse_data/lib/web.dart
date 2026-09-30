/// Browser database: sqlite3 compiled to WASM, persisted in OPFS when the
/// browser allows it, IndexedDB otherwise. Serve `sqlite3.wasm` and
/// `drift_worker.js` (drift 2.35.0 release assets) next to the app.
library;

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import 'src/database.dart';

/// [name] keys the browser storage: databases of different names on one
/// origin never see each other's data.
HermuseDatabase openWebDatabase({
  Uri? sqlite3Uri,
  Uri? driftWorkerUri,
  String name = 'hermuse',
}) => HermuseDatabase(
  DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: name,
        sqlite3Uri: sqlite3Uri ?? Uri.parse('sqlite3.wasm'),
        driftWorkerUri: driftWorkerUri ?? Uri.parse('drift_worker.js'),
      );
      return result.resolvedExecutor;
    }),
  ),
);
