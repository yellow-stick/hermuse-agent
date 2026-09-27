import 'dart:async';

import 'instance.dart';
import 'secrets.dart';

/// Persists instance metadata (never secrets).
abstract interface class InstanceStore {
  Future<List<HermesInstance>> load();
  Future<void> save(List<HermesInstance> instances, {String? primaryId});
  Future<String?> loadPrimaryId();
}

/// Non-persistent store for tests and first runs.
final class MemoryInstanceStore implements InstanceStore {
  List<HermesInstance> _instances = const [];
  String? _primary;

  @override
  Future<List<HermesInstance>> load() async => _instances;

  @override
  Future<String?> loadPrimaryId() async => _primary;

  @override
  Future<void> save(List<HermesInstance> instances, {String? primaryId}) async {
    _instances = List.unmodifiable(instances);
    _primary = primaryId;
  }
}

/// Thrown when an add/rename would duplicate a URL or label.
final class DuplicateInstance implements Exception {
  const DuplicateInstance(this.field, this.value);
  final String field;
  final Object value;

  @override
  String toString() => 'DuplicateInstance: $field "$value" already registered';
}

/// The user's Hermes instances, with an optional primary one.
final class HermesRegistry {
  HermesRegistry(this._store, this._secrets);

  final InstanceStore _store;
  final SecretStore _secrets;
  final _changes = StreamController<void>.broadcast();
  List<HermesInstance> _instances = const [];
  String? _primaryId;

  Stream<void> get changes => _changes.stream;
  List<HermesInstance> get instances => _instances;

  HermesInstance? get primary =>
      _instances.where((i) => i.id == _primaryId).firstOrNull ??
      _instances.firstOrNull;

  HermesInstance? byId(String id) =>
      _instances.where((i) => i.id == id).firstOrNull;

  Future<void> load() async {
    _instances = List.unmodifiable(await _store.load());
    _primaryId = await _store.loadPrimaryId();
    _changes.add(null);
  }

  Future<void> add(HermesInstance instance) async {
    _checkUnique(instance);
    await _commit([..._instances, instance], _primaryId ?? instance.id);
  }

  Future<void> update(HermesInstance instance) async {
    if (byId(instance.id) == null) throw StateError('unknown ${instance.id}');
    _checkUnique(instance);
    await _commit([
      for (final i in _instances) i.id == instance.id ? instance : i,
    ], _primaryId);
  }

  Future<void> setPrimary(String id) async {
    if (byId(id) == null) throw StateError('unknown $id');
    await _commit(_instances, id);
  }

  /// Removes the instance and every stored secret of it.
  Future<void> remove(String id) async {
    await _secrets.delete(id);
    await _commit(
      _instances.where((i) => i.id != id).toList(),
      _primaryId == id ? null : _primaryId,
    );
  }

  void _checkUnique(HermesInstance candidate) {
    final url = normalizeBaseUrl(candidate.baseUrl.toString());
    final label = candidate.label.trim().toLowerCase();
    for (final other in _instances) {
      if (other.id == candidate.id) continue;
      if (normalizeBaseUrl(other.baseUrl.toString()) == url &&
          other.profile == candidate.profile) {
        throw DuplicateInstance('url', url);
      }
      if (other.label.trim().toLowerCase() == label) {
        throw DuplicateInstance('label', candidate.label);
      }
    }
  }

  Future<void> _commit(List<HermesInstance> next, String? primaryId) async {
    await _store.save(next, primaryId: primaryId);
    _instances = List.unmodifiable(next);
    _primaryId = primaryId;
    _changes.add(null);
  }
}
