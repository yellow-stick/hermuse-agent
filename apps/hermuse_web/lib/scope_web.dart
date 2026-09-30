import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/web.dart';

/// Opens the drift WASM database [name] (client only; never imported during
/// SSR).
///
/// The asset URIs are absolute: the sqlite3 loader resolves them with
/// `new URL(url, globalThis.location.href)` inside the drift worker, and
/// some worker contexts reject bare relative paths.
Future<HermuseDatabase> openDatabase({required String name}) async {
  final base = Uri.base;
  final db = openWebDatabase(
    sqlite3Uri: base.resolve('sqlite3.wasm'),
    driftWorkerUri: base.resolve('drift_worker.js'),
    name: name,
  );
  // Force the worker connection up front so failures surface here,
  // not deep inside a provider read.
  await db.customSelect('SELECT 1').get();
  return db;
}
