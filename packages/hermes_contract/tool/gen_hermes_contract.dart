// Generates `lib/src/contract.g.dart` from `contract/gateway-contract.openrpc.json`.
//
// Run from `packages/hermes_contract`: `dart run tool/gen_hermes_contract.dart`.
// `test/drift_test.dart` fails when the committed output differs from a fresh run.
import 'dart:convert';
import 'dart:io';

const contractPath = 'contract/gateway-contract.openrpc.json';
const outputPath = 'lib/src/contract.g.dart';

void main() {
  final source = File(contractPath).readAsStringSync();
  File(outputPath).writeAsStringSync(generateContract(source));
  final format = Process.runSync(Platform.resolvedExecutable, [
    'format',
    outputPath,
  ]);
  if (format.exitCode != 0) {
    stderr.write(format.stderr);
    exit(format.exitCode);
  }
}

/// Returns the unformatted Dart source for [openRpcJson].
String generateContract(String openRpcJson) =>
    _Generator(jsonDecode(openRpcJson) as Map<String, Object?>).run();

const _reserved = {
  'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case', //
  'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
  'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
  'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
  'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
  'late', 'library', 'mixin', 'new', 'null', 'of', 'on', 'operator', 'part',
  'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
  'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'type',
  'typedef', 'var', 'void', 'when', 'while', 'with', 'yield',
  // Object members and generated members.
  'hashCode', 'runtimeType', 'toString', 'noSuchMethod', 'toJson', 'fromJson',
};

/// Extra names an enum member must avoid.
const _enumReserved = {'values', 'index', 'name', 'wire', 'fromWire'};

const _coreNames = {
  'Error', 'List', 'Map', 'Set', 'Type', 'Duration', 'Object', 'Symbol', //
  'Record', 'Enum', 'Pattern', 'Match', 'Uri', 'Iterable', 'Stream',
  'Future', 'Null', 'String', 'Comparable', 'Exception', 'Sink', 'Function',
  'DateTime', 'Invocation', 'Iterator', 'RegExp', 'StackTrace', 'Expando',
};

String _words(String raw, {required bool upperFirst}) {
  final parts = raw
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return upperFirst ? 'Empty' : 'empty';
  final buf = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i].toLowerCase();
    buf.write(i == 0 && !upperFirst ? p : p[0].toUpperCase() + p.substring(1));
  }
  var out = buf.toString();
  if (RegExp(r'^[0-9]').hasMatch(out)) out = upperFirst ? 'V$out' : 'v$out';
  return out;
}

String _member(String raw, {bool enumMember = false}) {
  final id = _words(raw, upperFirst: false);
  final clash =
      _reserved.contains(id) || (enumMember && _enumReserved.contains(id));
  return clash ? '$id\$' : id;
}

String _typeName(String raw) {
  final id = _words(raw, upperFirst: true);
  return _coreNames.contains(id) ? 'Hermes$id' : id;
}

String _str(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";

String _literal(Object value) => value is String ? _str(value) : '$value';

String _doc(Object? text, [String indent = '']) {
  if (text is! String || text.trim().isEmpty) return '';
  final lines = text.trim().split('\n');
  final body = lines.map((l) => '$indent/// ${l.trimRight()}'.trimRight());
  return '${body.join('\n')}\n';
}

/// A Dart view of one JSON Schema.
final class _T {
  const _T(this.type, this.decode, this.encode, {this.nullable = false});

  /// Dart type without the nullability suffix.
  final String type;

  /// Builds a decode expression from a non-null `Object` expression.
  final String Function(String v) decode;

  /// Builds a JSON encode expression from a non-null Dart value expression.
  final String Function(String v) encode;
  final bool nullable;

  _T asNullable() => _T(type, decode, encode, nullable: true);
  String get full => nullable && type != 'Object?' ? '$type?' : type;
}

String _id(String v) => v;

final _object = _T('Object?', _id, _id, nullable: true);
final _map = _T(
  'Map<String, Object?>',
  (v) => '($v as Map<String, Object?>)',
  _id,
);

final class _Union {
  _Union(this.name, this.property, this.mapping);
  final String name;
  final String property;
  final Map<String, String> mapping; // wire value -> schema name
}

final class _Generator {
  _Generator(this.doc)
    : schemas = ((doc['components'] as Map)['schemas'] as Map)
          .cast<String, Map<String, Object?>>();

  final Map<String, Object?> doc;
  final Map<String, Map<String, Object?>> schemas;
  final out = StringBuffer();
  final Map<String, String> classNames = {}; // schema name -> dart name
  final Map<String, _Union> unions = {}; // union key -> union
  final Map<String, List<String>> implementsOf = {}; // schema -> unions
  final List<String> inlineEnums = [];
  final Set<String> usedTypeNames = {};

  String _claim(String name) {
    if (!usedTypeNames.add(name)) {
      throw StateError('Generated type name collision: $name');
    }
    return name;
  }

  String run() {
    for (final name in schemas.keys) {
      classNames[name] = _claim(_typeName(name));
    }
    // Discover discriminated unions first so variants can implement them.
    for (final entry in schemas.entries) {
      final props = (entry.value['properties'] as Map?) ?? const {};
      for (final p in props.values) {
        _discoverUnions(p as Map<String, Object?>);
      }
    }
    out.writeln('// GENERATED by tool/gen_hermes_contract.dart — do not edit.');
    out.writeln('// Source: ${_info()}');
    out.writeln('// ignore_for_file: constant_identifier_names');
    out.writeln();
    out.writeln("import 'json_object.dart';");
    out.writeln("import 'method.dart';");
    out.writeln();
    for (final u in unions.values) {
      _emitUnion(u);
    }
    for (final entry in schemas.entries) {
      _emitSchema(entry.key, entry.value);
    }
    _emitMethods();
    _emitEvents();
    _emitServerRequests();
    for (final e in inlineEnums) {
      out.write(e);
    }
    return out.toString();
  }

  String _info() {
    final info = doc['info'] as Map;
    return '${info['title']} (OpenRPC ${doc['openrpc']}, contract v${info['version']})';
  }

  String _refName(Map<String, Object?> s) =>
      (s[r'$ref'] as String).split('/').last;

  void _discoverUnions(Map<String, Object?> s) {
    if (s['oneOf'] case final List<Object?> _) {
      final disc = s['discriminator'] as Map<String, Object?>?;
      if (disc == null) throw StateError('oneOf without discriminator: $s');
      final property = disc['propertyName'] as String;
      final mapping = {
        for (final e in (disc['mapping'] as Map).entries)
          e.key as String: (e.value as String).split('/').last,
      };
      final key =
          '$property|${(mapping.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join(',')}';
      if (unions.containsKey(key)) return;
      final title = s['title'] as String? ?? mapping.values.first;
      final name = _claim('${_typeName(title)}Union');
      unions[key] = _Union(name, property, mapping);
      for (final variant in mapping.values.toSet()) {
        (implementsOf[variant] ??= []).add(name);
      }
      return;
    }
    for (final k in ['anyOf', 'items']) {
      final v = s[k];
      if (v is List) {
        for (final x in v) {
          _discoverUnions(x as Map<String, Object?>);
        }
      } else if (v is Map) {
        _discoverUnions(v.cast<String, Object?>());
      }
    }
    if (s['additionalProperties'] case final Map<Object?, Object?> ap) {
      _discoverUnions(ap.cast<String, Object?>());
    }
  }

  _Union _unionFor(Map<String, Object?> s) {
    final disc = s['discriminator'] as Map<String, Object?>;
    final mapping = {
      for (final e in (disc['mapping'] as Map).entries)
        e.key as String: (e.value as String).split('/').last,
    };
    final key =
        '${disc['propertyName']}|${(mapping.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join(',')}';
    return unions[key]!;
  }

  /// Maps a schema to a Dart type; [owner]/[field] name inline enums.
  _T _type(Map<String, Object?> s, String owner, String field) {
    if (s.containsKey(r'$ref')) {
      final ref = _refName(s);
      final target = schemas[ref]!;
      final dart = classNames[ref]!;
      if (target.containsKey('enum')) {
        return _T(
          dart,
          (v) => '$dart.fromWire($v as String)',
          (v) => '$v.wire',
        );
      }
      return _T(
        dart,
        (v) => '$dart.fromJson($v as Map<String, Object?>)',
        (v) => '$v.toJson()',
      );
    }
    if (s.containsKey('oneOf')) {
      final u = _unionFor(s);
      return _T(
        u.name,
        (v) => '${u.name}.fromJson($v as Map<String, Object?>)',
        (v) => '$v.toJson()',
      );
    }
    if (s['anyOf'] case final List<Object?> any) {
      final options = any.cast<Map<String, Object?>>();
      final hasNull = options.any((o) => o['type'] == 'null');
      final rest = options.where((o) => o['type'] != 'null').toList();
      if (rest.length == 1) {
        final t = _type(rest.single, owner, field);
        return hasNull ? t.asNullable() : t;
      }
      final kinds = rest.map((o) => o['type']).toSet();
      if (kinds.length == 2 && kinds.containsAll(['integer', 'number'])) {
        final t = _T('num', (v) => '($v as num)', _id);
        return hasNull ? t.asNullable() : t;
      }
      return _object;
    }
    if (s.containsKey('const')) {
      return _T('String', (v) => '($v as String)', _id);
    }
    if (s['enum'] case final List<Object?> values) {
      final name = _claim('${classNames[owner] ?? owner}${_typeName(field)}');
      inlineEnums.add(_enumSource(name, s, values.cast<String>()));
      return _T(name, (v) => '$name.fromWire($v as String)', (v) => '$v.wire');
    }
    switch (s['type']) {
      case 'string':
        return _T('String', (v) => '($v as String)', _id);
      case 'integer':
        return _T('int', (v) => '($v as num).toInt()', _id);
      case 'number':
        return _T('double', (v) => '($v as num).toDouble()', _id);
      case 'boolean':
        return _T('bool', (v) => '($v as bool)', _id);
      case 'null':
      case null:
        return _object;
      case 'array':
        final item = _type(
          (s['items'] as Map?)?.cast<String, Object?>() ?? const {},
          owner,
          field,
        );
        final passthrough = _isPassthrough(item);
        return _T(
          'List<${item.full}>',
          (v) => passthrough
              ? '($v as List<Object?>).cast<${item.full}>()'
              : '[for (final e in $v as List<Object?>) ${_decodeNullable(item, 'e')}]',
          (v) => passthrough
              ? v
              : '[for (final e in $v) ${_encodeNullable(item, 'e')}]',
        );
      case 'object':
        if (s.containsKey('properties')) {
          throw StateError('Inline object in $owner.$field is unsupported');
        }
        final ap = s['additionalProperties'];
        if (ap is! Map || ap.isEmpty) return _map;
        final value = _type(ap.cast<String, Object?>(), owner, field);
        final passthrough = _isPassthrough(value);
        return _T(
          'Map<String, ${value.full}>',
          (v) => passthrough
              ? '($v as Map<String, Object?>).cast<String, ${value.full}>()'
              : '{for (final e in ($v as Map<String, Object?>).entries) e.key: ${_decodeNullable(value, 'e.value')}}',
          (v) => passthrough
              ? v
              : '{for (final e in $v.entries) e.key: ${_encodeNullable(value, 'e.value')}}',
        );
    }
    throw StateError('Unsupported schema in $owner.$field: $s');
  }

  bool _isPassthrough(_T t) =>
      const {
        'String',
        'bool',
        'num',
        'Object?',
        'Map<String, Object?>',
      }.contains(t.type) &&
      t.encode('x') == 'x';

  String _decodeNullable(_T t, String v) => t.nullable
      ? 'switch ($v) { null => null, final Object v => ${t.decode('v')} }'
      : t.decode(v);

  String _encodeNullable(_T t, String v) {
    final sample = t.encode('x');
    if (sample == 'x') return v;
    if (t.nullable && sample.startsWith('x.')) {
      return '$v?${sample.substring(1)}';
    }
    return t.nullable ? '$v == null ? null : ${t.encode('$v!')}' : t.encode(v);
  }

  String _enumSource(String name, Map<String, Object?> s, List<String> values) {
    final buf = StringBuffer();
    buf.write(_doc(s['description']));
    buf.writeln('enum $name {');
    final members = <String>{};
    for (final v in values) {
      final m = _member(v, enumMember: true);
      if (!members.add(m)) throw StateError('Enum member collision $name.$m');
      buf.writeln('  $m(${_str(v)}),');
    }
    buf.writeln('\n  /// A value this client version does not know.');
    buf.writeln("  \$unknown('');");
    buf.writeln('\n  const $name(this.wire);');
    buf.writeln('\n  /// The JSON value.');
    buf.writeln('  final String wire;');
    buf.writeln(
      '\n  /// Decodes [wire]; unknown values map to [\$unknown] so newer servers stay readable.',
    );
    buf.writeln(
      '  static $name fromWire(String wire) => values.firstWhere((e) => e.wire == wire, orElse: () => \$unknown);',
    );
    buf.writeln('}\n');
    return buf.toString();
  }

  String? _defaultLiteral(Object? value, _T t, Map<String, Object?> schema) {
    if (value == null) return null;
    if (schema.containsKey(r'$ref')) {
      final ref = _refName(schema);
      if (schemas[ref]!.containsKey('enum') && value is String) {
        return '${classNames[ref]}.${_member(value, enumMember: true)}';
      }
      return null;
    }
    return switch (value) {
      String() when t.type == 'String' => _str(value),
      bool() when t.type == 'bool' => '$value',
      int() when t.type == 'int' || t.type == 'num' => '$value',
      num() when t.type == 'double' || t.type == 'num' =>
        value.toDouble().toString(),
      List() when value.isEmpty && t.type.startsWith('List<') => 'const []',
      Map() when value.isEmpty && t.type.startsWith('Map<') => 'const {}',
      _ => null,
    };
  }

  void _emitSchema(String name, Map<String, Object?> s) {
    final dart = classNames[name]!;
    if (s['enum'] case final List<Object?> values) {
      out.write(_enumSource(dart, s, values.cast<String>()));
      return;
    }
    if (s['type'] != 'object') throw StateError('Unsupported top schema $name');
    final props = ((s['properties'] as Map?) ?? const {})
        .cast<String, Map<String, Object?>>();
    final required = ((s['required'] as List?) ?? const []).cast<String>();
    final fields = <_Field>[];
    final memberNames = <String>{};
    for (final e in props.entries) {
      final ps = e.value;
      final member = _member(e.key);
      if (!memberNames.add(member)) {
        throw StateError('Field name collision $name.$member');
      }
      if (ps.containsKey('const')) {
        fields.add(_Field.constant(e.key, member, ps['const']!, ps));
        continue;
      }
      var t = _type(ps, name, e.key);
      final isRequired = required.contains(e.key);
      final def = isRequired ? null : _defaultLiteral(ps['default'], t, ps);
      if (!isRequired && def == null) t = t.asNullable();
      fields.add(_Field(e.key, member, t, ps, isRequired, def));
    }
    out.write(_doc(s['description']));
    final interfaces = ['JsonObject', ...?implementsOf[name]];
    out.writeln('final class $dart implements ${interfaces.join(', ')} {');
    final params = fields.where((f) => f.constant == null).toList();
    if (params.isEmpty) {
      out.writeln('  const $dart();');
    } else {
      out.writeln('  const $dart({');
      for (final f in params) {
        if (f.required) {
          out.writeln('    required this.${f.member},');
        } else if (f.defaultLiteral != null) {
          out.writeln('    this.${f.member} = ${f.defaultLiteral},');
        } else {
          out.writeln('    this.${f.member},');
        }
      }
      out.writeln('  });');
    }
    out.writeln();
    out.writeln(
      '  factory $dart.fromJson(Map<String, Object?> json) => ${params.isEmpty ? 'const ' : ''}$dart(',
    );
    for (final f in params) {
      final raw = "json[${_str(f.key)}]";
      final t = f.type!;
      if (f.required && !t.nullable) {
        out.writeln(
          "    ${f.member}: ${t.decode("_required(json, ${_str(f.key)}, ${_str(dart)})")},",
        );
      } else if (f.defaultLiteral != null) {
        out.writeln(
          '    ${f.member}: switch ($raw) { null => ${f.defaultLiteral}, final Object v => ${t.decode('v')} },',
        );
      } else {
        out.writeln('    ${f.member}: ${_decodeNullable(t, raw)},');
      }
    }
    out.writeln('  );');
    for (final f in fields) {
      out.writeln();
      out.write(_doc(f.schema['description'], '  '));
      if (f.constant != null) {
        final c = f.constant!;
        final type = switch (c) {
          String() => 'String',
          int() => 'int',
          bool() => 'bool',
          _ => throw StateError('const $c'),
        };
        out.writeln('  $type get ${f.member} => ${_literal(c)};');
      } else {
        out.writeln('  final ${f.type!.full} ${f.member};');
      }
    }
    out.writeln();
    out.writeln('  @override');
    out.writeln('  Map<String, Object?> toJson() => {');
    for (final f in fields) {
      final key = _str(f.key);
      if (f.constant != null) {
        out.writeln('    $key: ${_literal(f.constant!)},');
        continue;
      }
      final t = f.type!;
      if (t.nullable && !f.required) {
        final enc = t.encode('x') == 'x' ? f.member : t.encode('${f.member}!');
        out.writeln('    if (${f.member} != null) $key: $enc,');
      } else if (t.nullable) {
        out.writeln('    $key: ${_encodeNullable(t, f.member)},');
      } else {
        out.writeln('    $key: ${t.encode(f.member)},');
      }
    }
    out.writeln('  };');
    out.writeln('}\n');
  }

  void _emitUnion(_Union u) {
    out.writeln('/// Discriminated on `${u.property}`.');
    out.writeln('sealed class ${u.name} implements JsonObject {');
    out.writeln(
      '  factory ${u.name}.fromJson(Map<String, Object?> json) => switch (json[${_str(u.property)}]) {',
    );
    for (final e in u.mapping.entries) {
      out.writeln(
        '    ${_str(e.key)} => ${classNames[e.value]}.fromJson(json),',
      );
    }
    out.writeln(
      "    final Object? v => throw FormatException('${u.name}: unknown ${u.property} \$v'),",
    );
    out.writeln('  };');
    out.writeln('}\n');
  }

  String _schemaDart(Map<String, Object?> s) => classNames[_refName(s)]!;

  void _emitMethods() {
    final methods = (doc['methods'] as List).cast<Map<String, Object?>>();
    out.writeln('/// Every client → server method of the gateway.');
    out.writeln('abstract final class HermesMethods {');
    final names = <String>{};
    for (final m in methods) {
      final wire = m['name'] as String;
      final member = _member(wire);
      if (!names.add(member)) throw StateError('Method collision $member');
      final params = ((m['params'] as List).single as Map)['schema'] as Map;
      final result = (m['result'] as Map)['schema'] as Map;
      final p = _schemaDart(params.cast());
      final r = _schemaDart(result.cast());
      out.write(_doc(m['summary'], '  '));
      out.writeln(
        '  static const $member = HermesMethod<$p, $r>(${_str(wire)}, $r.fromJson);\n',
      );
    }
    out.writeln('  /// All methods by wire name.');
    out.writeln(
      '  static const Map<String, HermesMethod<JsonObject, Object>> all = {',
    );
    for (final m in methods) {
      final wire = m['name'] as String;
      out.writeln('    ${_str(wire)}: ${_member(wire)},');
    }
    out.writeln('  };');
    out.writeln('}\n');
  }

  void _emitEvents() {
    final notes = (doc['x-notifications'] as List).cast<Map<String, Object?>>();
    out.writeln('''
/// A gateway notification: `{"method": "event", "params": {"type", "session_id", "seq", "payload"}}`.
sealed class HermesEvent {
  const HermesEvent({this.sessionId, this.seq});

  /// Owning session; empty or null for app-level events.
  final String? sessionId;

  /// Per-session monotonic sequence number used by `session.events.since`.
  final int? seq;

  /// The wire `type`.
  String get type;

  /// Decodes the `params` of an `event` frame.
  static HermesEvent fromParams(Map<String, Object?> params) {
    final sessionId = params['session_id'] as String?;
    final seq = (params['seq'] as num?)?.toInt();
    final payload = params['payload'];
    final body = payload is Map<String, Object?> ? payload : const <String, Object?>{};
    return switch (params['type']) {''');
    final events = <String, String>{};
    for (final n in notes) {
      final wire = n['name'] as String;
      final cls = _claim('${_typeName(wire)}Event');
      final schema = ((n['params'] as List).single as Map)['schema'] as Map;
      final String? payloadType;
      if (schema.containsKey(r'$ref')) {
        payloadType = _schemaDart(schema.cast());
        out.writeln(
          '      ${_str(wire)} => $cls(sessionId: sessionId, seq: seq, payload: $payloadType.fromJson(body)),',
        );
      } else if (schema['type'] == 'object' &&
          !schema.containsKey('properties')) {
        payloadType = schema['additionalProperties'] == true
            ? 'Map<String, Object?>'
            : null;
        out.writeln(
          '      ${_str(wire)} => $cls(sessionId: sessionId, seq: seq${payloadType == null ? '' : ', payload: body'}),',
        );
      } else {
        throw StateError('Unsupported notification payload $wire: $schema');
      }
      final summary = _doc(n['summary']);
      events[cls] =
          '''
$summary final class $cls extends HermesEvent {
  const $cls({super.sessionId, super.seq${payloadType == null ? '' : ', required this.payload'}});

  @override
  String get type => ${_str(wire)};
${payloadType == null ? '' : '\n  /// Event body.\n  final $payloadType payload;\n'}}
''';
    }
    out.writeln('''
      final Object? type => UnknownHermesEvent(
          type: type is String ? type : '',
          sessionId: sessionId,
          seq: seq,
          payload: payload,
        ),
    };
  }
}

/// An event type this client version does not know.
final class UnknownHermesEvent extends HermesEvent {
  const UnknownHermesEvent({required this.type, super.sessionId, super.seq, this.payload});

  @override
  final String type;

  /// Raw payload.
  final Object? payload;
}
''');
    for (final e in events.values) {
      out.writeln(e);
    }
  }

  void _emitServerRequests() {
    final reqs = (doc['x-server-requests'] as List)
        .cast<Map<String, Object?>>();
    out.writeln('''
/// A server → client request; answer with a JSON-RPC response carrying [id].
sealed class HermesServerRequest<R extends JsonObject> {
  const HermesServerRequest({required this.id, required this.sessionId});

  /// JSON-RPC request id (`srq-…`); the response must reuse it.
  final String id;

  /// Owning session; empty for app-level requests.
  final String sessionId;

  /// The wire method.
  String get method;

  /// Decodes a request frame, or returns null for a method this client does not know.
  static HermesServerRequest<JsonObject>? fromFrame(String id, String method, Map<String, Object?> params) {
    final sessionId = params['session_id'] as String? ?? '';
    return switch (method) {''');
    final classes = <String>[];
    for (final r in reqs) {
      final wire = r['name'] as String;
      final cls = _claim('${_typeName(wire)}ServerRequest');
      final p = _schemaDart(
        (((r['params'] as List).single as Map)['schema'] as Map).cast(),
      );
      final res = _schemaDart(((r['result'] as Map)['schema'] as Map).cast());
      out.writeln(
        '      ${_str(wire)} => $cls(id: id, sessionId: sessionId, params: $p.fromJson(params)),',
      );
      classes.add('''
${_doc(r['summary'])}final class $cls extends HermesServerRequest<$res> {
  const $cls({required super.id, required super.sessionId, required this.params});

  @override
  String get method => ${_str(wire)};

  /// Request body.
  final $p params;
}
''');
    }
    out.writeln('      _ => null,');
    out.writeln('    };');
    out.writeln('  }');
    out.writeln('}\n');
    classes.forEach(out.writeln);
    out.writeln('''
Object _required(Map<String, Object?> json, String key, String owner) =>
    json[key] ?? (throw FormatException('\$owner: missing "\$key"'));
''');
  }
}

final class _Field {
  _Field(
    this.key,
    this.member,
    this.type,
    this.schema,
    this.required,
    this.defaultLiteral,
  ) : constant = null;

  _Field.constant(this.key, this.member, this.constant, this.schema)
    : type = null,
      required = false,
      defaultLiteral = null;

  final String key;
  final String member;
  final _T? type;
  final Map<String, Object?> schema;
  final bool required;
  final String? defaultLiteral;
  final Object? constant;
}
