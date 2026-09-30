import 'package:hermuse_data/hermuse_data.dart';

/// SSR stub: the server pre-render never opens the database.
Future<HermuseDatabase> openDatabase({required String name}) =>
    throw StateError('database is client-only');
