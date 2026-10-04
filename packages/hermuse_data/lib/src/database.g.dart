// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class Instances extends Table with TableInfo<Instances, InstanceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Instances(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE COLLATE NOCASE',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _authMeta = const VerificationMeta('auth');
  late final GeneratedColumn<String> auth = GeneratedColumn<String>(
    'auth',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _profileMeta = const VerificationMeta(
    'profile',
  );
  late final GeneratedColumn<String> profile = GeneratedColumn<String>(
    'profile',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
    'is_primary',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    label,
    kind,
    baseUrl,
    auth,
    profile,
    isPrimary,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'instances';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstanceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('auth')) {
      context.handle(
        _authMeta,
        auth.isAcceptableOrUnknown(data['auth']!, _authMeta),
      );
    } else if (isInserting) {
      context.missing(_authMeta);
    }
    if (data.containsKey('profile')) {
      context.handle(
        _profileMeta,
        profile.isAcceptableOrUnknown(data['profile']!, _profileMeta),
      );
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InstanceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstanceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      auth: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth'],
      )!,
      profile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile'],
      ),
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_primary'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  Instances createAlias(String alias) {
    return Instances(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class InstanceRow extends DataClass implements Insertable<InstanceRow> {
  final String id;
  final String label;
  final String kind;
  final String baseUrl;
  final String auth;
  final String? profile;
  final bool isPrimary;
  final int position;
  const InstanceRow({
    required this.id,
    required this.label,
    required this.kind,
    required this.baseUrl,
    required this.auth,
    this.profile,
    required this.isPrimary,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['label'] = Variable<String>(label);
    map['kind'] = Variable<String>(kind);
    map['base_url'] = Variable<String>(baseUrl);
    map['auth'] = Variable<String>(auth);
    if (!nullToAbsent || profile != null) {
      map['profile'] = Variable<String>(profile);
    }
    map['is_primary'] = Variable<bool>(isPrimary);
    map['position'] = Variable<int>(position);
    return map;
  }

  InstancesCompanion toCompanion(bool nullToAbsent) {
    return InstancesCompanion(
      id: Value(id),
      label: Value(label),
      kind: Value(kind),
      baseUrl: Value(baseUrl),
      auth: Value(auth),
      profile: profile == null && nullToAbsent
          ? const Value.absent()
          : Value(profile),
      isPrimary: Value(isPrimary),
      position: Value(position),
    );
  }

  factory InstanceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstanceRow(
      id: serializer.fromJson<String>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      kind: serializer.fromJson<String>(json['kind']),
      baseUrl: serializer.fromJson<String>(json['base_url']),
      auth: serializer.fromJson<String>(json['auth']),
      profile: serializer.fromJson<String?>(json['profile']),
      isPrimary: serializer.fromJson<bool>(json['is_primary']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'label': serializer.toJson<String>(label),
      'kind': serializer.toJson<String>(kind),
      'base_url': serializer.toJson<String>(baseUrl),
      'auth': serializer.toJson<String>(auth),
      'profile': serializer.toJson<String?>(profile),
      'is_primary': serializer.toJson<bool>(isPrimary),
      'position': serializer.toJson<int>(position),
    };
  }

  InstanceRow copyWith({
    String? id,
    String? label,
    String? kind,
    String? baseUrl,
    String? auth,
    Value<String?> profile = const Value.absent(),
    bool? isPrimary,
    int? position,
  }) => InstanceRow(
    id: id ?? this.id,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    baseUrl: baseUrl ?? this.baseUrl,
    auth: auth ?? this.auth,
    profile: profile.present ? profile.value : this.profile,
    isPrimary: isPrimary ?? this.isPrimary,
    position: position ?? this.position,
  );
  InstanceRow copyWithCompanion(InstancesCompanion data) {
    return InstanceRow(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      kind: data.kind.present ? data.kind.value : this.kind,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      auth: data.auth.present ? data.auth.value : this.auth,
      profile: data.profile.present ? data.profile.value : this.profile,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstanceRow(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('kind: $kind, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('auth: $auth, ')
          ..write('profile: $profile, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, label, kind, baseUrl, auth, profile, isPrimary, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstanceRow &&
          other.id == this.id &&
          other.label == this.label &&
          other.kind == this.kind &&
          other.baseUrl == this.baseUrl &&
          other.auth == this.auth &&
          other.profile == this.profile &&
          other.isPrimary == this.isPrimary &&
          other.position == this.position);
}

class InstancesCompanion extends UpdateCompanion<InstanceRow> {
  final Value<String> id;
  final Value<String> label;
  final Value<String> kind;
  final Value<String> baseUrl;
  final Value<String> auth;
  final Value<String?> profile;
  final Value<bool> isPrimary;
  final Value<int> position;
  final Value<int> rowid;
  const InstancesCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.kind = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.auth = const Value.absent(),
    this.profile = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstancesCompanion.insert({
    required String id,
    required String label,
    required String kind,
    required String baseUrl,
    required String auth,
    this.profile = const Value.absent(),
    this.isPrimary = const Value.absent(),
    required int position,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       label = Value(label),
       kind = Value(kind),
       baseUrl = Value(baseUrl),
       auth = Value(auth),
       position = Value(position);
  static Insertable<InstanceRow> custom({
    Expression<String>? id,
    Expression<String>? label,
    Expression<String>? kind,
    Expression<String>? baseUrl,
    Expression<String>? auth,
    Expression<String>? profile,
    Expression<bool>? isPrimary,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (kind != null) 'kind': kind,
      if (baseUrl != null) 'base_url': baseUrl,
      if (auth != null) 'auth': auth,
      if (profile != null) 'profile': profile,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstancesCompanion copyWith({
    Value<String>? id,
    Value<String>? label,
    Value<String>? kind,
    Value<String>? baseUrl,
    Value<String>? auth,
    Value<String?>? profile,
    Value<bool>? isPrimary,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return InstancesCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      baseUrl: baseUrl ?? this.baseUrl,
      auth: auth ?? this.auth,
      profile: profile ?? this.profile,
      isPrimary: isPrimary ?? this.isPrimary,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (auth.present) {
      map['auth'] = Variable<String>(auth.value);
    }
    if (profile.present) {
      map['profile'] = Variable<String>(profile.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstancesCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('kind: $kind, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('auth: $auth, ')
          ..write('profile: $profile, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Sessions extends Table with TableInfo<Sessions, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Sessions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _instanceIdMeta = const VerificationMeta(
    'instanceId',
  );
  late final GeneratedColumn<String> instanceId = GeneratedColumn<String>(
    'instance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES instances(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _profileMeta = const VerificationMeta(
    'profile',
  );
  late final GeneratedColumn<String> profile = GeneratedColumn<String>(
    'profile',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'default\'',
    defaultValue: const CustomExpression('\'default\''),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'\'',
    defaultValue: const CustomExpression('\'\''),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _pinnedAtMeta = const VerificationMeta(
    'pinnedAt',
  );
  late final GeneratedColumn<int> pinnedAt = GeneratedColumn<int>(
    'pinned_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    instanceId,
    profile,
    sessionId,
    title,
    parentId,
    updatedAt,
    archived,
    pinnedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('instance_id')) {
      context.handle(
        _instanceIdMeta,
        instanceId.isAcceptableOrUnknown(data['instance_id']!, _instanceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_instanceIdMeta);
    }
    if (data.containsKey('profile')) {
      context.handle(
        _profileMeta,
        profile.isAcceptableOrUnknown(data['profile']!, _profileMeta),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('pinned_at')) {
      context.handle(
        _pinnedAtMeta,
        pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {instanceId, profile, sessionId};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      instanceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instance_id'],
      )!,
      profile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      pinnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pinned_at'],
      ),
    );
  }

  @override
  Sessions createAlias(String alias) {
    return Sessions(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(instance_id, profile, session_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final String instanceId;
  final String profile;
  final String sessionId;
  final String title;

  /// Stored id of the main session this side chat branches from.
  final String? parentId;

  /// Last activity (ms since epoch): creation or last finished turn.
  final int updatedAt;

  /// Side chat hidden on the server (`session.set_hidden`), listed under
  /// "Archived chats".
  final bool archived;

  /// When the side chat was pinned (ms since epoch); null when not pinned.
  final int? pinnedAt;
  const SessionRow({
    required this.instanceId,
    required this.profile,
    required this.sessionId,
    required this.title,
    this.parentId,
    required this.updatedAt,
    required this.archived,
    this.pinnedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['instance_id'] = Variable<String>(instanceId);
    map['profile'] = Variable<String>(profile);
    map['session_id'] = Variable<String>(sessionId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['archived'] = Variable<bool>(archived);
    if (!nullToAbsent || pinnedAt != null) {
      map['pinned_at'] = Variable<int>(pinnedAt);
    }
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      instanceId: Value(instanceId),
      profile: Value(profile),
      sessionId: Value(sessionId),
      title: Value(title),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      updatedAt: Value(updatedAt),
      archived: Value(archived),
      pinnedAt: pinnedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pinnedAt),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      instanceId: serializer.fromJson<String>(json['instance_id']),
      profile: serializer.fromJson<String>(json['profile']),
      sessionId: serializer.fromJson<String>(json['session_id']),
      title: serializer.fromJson<String>(json['title']),
      parentId: serializer.fromJson<String?>(json['parent_id']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
      archived: serializer.fromJson<bool>(json['archived']),
      pinnedAt: serializer.fromJson<int?>(json['pinned_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'instance_id': serializer.toJson<String>(instanceId),
      'profile': serializer.toJson<String>(profile),
      'session_id': serializer.toJson<String>(sessionId),
      'title': serializer.toJson<String>(title),
      'parent_id': serializer.toJson<String?>(parentId),
      'updated_at': serializer.toJson<int>(updatedAt),
      'archived': serializer.toJson<bool>(archived),
      'pinned_at': serializer.toJson<int?>(pinnedAt),
    };
  }

  SessionRow copyWith({
    String? instanceId,
    String? profile,
    String? sessionId,
    String? title,
    Value<String?> parentId = const Value.absent(),
    int? updatedAt,
    bool? archived,
    Value<int?> pinnedAt = const Value.absent(),
  }) => SessionRow(
    instanceId: instanceId ?? this.instanceId,
    profile: profile ?? this.profile,
    sessionId: sessionId ?? this.sessionId,
    title: title ?? this.title,
    parentId: parentId.present ? parentId.value : this.parentId,
    updatedAt: updatedAt ?? this.updatedAt,
    archived: archived ?? this.archived,
    pinnedAt: pinnedAt.present ? pinnedAt.value : this.pinnedAt,
  );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      instanceId: data.instanceId.present
          ? data.instanceId.value
          : this.instanceId,
      profile: data.profile.present ? data.profile.value : this.profile,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      title: data.title.present ? data.title.value : this.title,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      archived: data.archived.present ? data.archived.value : this.archived,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('instanceId: $instanceId, ')
          ..write('profile: $profile, ')
          ..write('sessionId: $sessionId, ')
          ..write('title: $title, ')
          ..write('parentId: $parentId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archived: $archived, ')
          ..write('pinnedAt: $pinnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    instanceId,
    profile,
    sessionId,
    title,
    parentId,
    updatedAt,
    archived,
    pinnedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.instanceId == this.instanceId &&
          other.profile == this.profile &&
          other.sessionId == this.sessionId &&
          other.title == this.title &&
          other.parentId == this.parentId &&
          other.updatedAt == this.updatedAt &&
          other.archived == this.archived &&
          other.pinnedAt == this.pinnedAt);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> instanceId;
  final Value<String> profile;
  final Value<String> sessionId;
  final Value<String> title;
  final Value<String?> parentId;
  final Value<int> updatedAt;
  final Value<bool> archived;
  final Value<int?> pinnedAt;
  final Value<int> rowid;
  const SessionsCompanion({
    this.instanceId = const Value.absent(),
    this.profile = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.title = const Value.absent(),
    this.parentId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archived = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String instanceId,
    this.profile = const Value.absent(),
    required String sessionId,
    this.title = const Value.absent(),
    this.parentId = const Value.absent(),
    required int updatedAt,
    this.archived = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : instanceId = Value(instanceId),
       sessionId = Value(sessionId),
       updatedAt = Value(updatedAt);
  static Insertable<SessionRow> custom({
    Expression<String>? instanceId,
    Expression<String>? profile,
    Expression<String>? sessionId,
    Expression<String>? title,
    Expression<String>? parentId,
    Expression<int>? updatedAt,
    Expression<bool>? archived,
    Expression<int>? pinnedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (instanceId != null) 'instance_id': instanceId,
      if (profile != null) 'profile': profile,
      if (sessionId != null) 'session_id': sessionId,
      if (title != null) 'title': title,
      if (parentId != null) 'parent_id': parentId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (archived != null) 'archived': archived,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? instanceId,
    Value<String>? profile,
    Value<String>? sessionId,
    Value<String>? title,
    Value<String?>? parentId,
    Value<int>? updatedAt,
    Value<bool>? archived,
    Value<int?>? pinnedAt,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      instanceId: instanceId ?? this.instanceId,
      profile: profile ?? this.profile,
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      parentId: parentId ?? this.parentId,
      updatedAt: updatedAt ?? this.updatedAt,
      archived: archived ?? this.archived,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (instanceId.present) {
      map['instance_id'] = Variable<String>(instanceId.value);
    }
    if (profile.present) {
      map['profile'] = Variable<String>(profile.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<int>(pinnedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('instanceId: $instanceId, ')
          ..write('profile: $profile, ')
          ..write('sessionId: $sessionId, ')
          ..write('title: $title, ')
          ..write('parentId: $parentId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archived: $archived, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Messages extends Table with TableInfo<Messages, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Messages(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _instanceIdMeta = const VerificationMeta(
    'instanceId',
  );
  late final GeneratedColumn<String> instanceId = GeneratedColumn<String>(
    'instance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _profileMeta = const VerificationMeta(
    'profile',
  );
  late final GeneratedColumn<String> profile = GeneratedColumn<String>(
    'profile',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'default\'',
    defaultValue: const CustomExpression('\'default\''),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _bodyTextMeta = const VerificationMeta(
    'bodyText',
  );
  late final GeneratedColumn<String> bodyText = GeneratedColumn<String>(
    'body_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    instanceId,
    profile,
    sessionId,
    messageId,
    author,
    bodyText,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('instance_id')) {
      context.handle(
        _instanceIdMeta,
        instanceId.isAcceptableOrUnknown(data['instance_id']!, _instanceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_instanceIdMeta);
    }
    if (data.containsKey('profile')) {
      context.handle(
        _profileMeta,
        profile.isAcceptableOrUnknown(data['profile']!, _profileMeta),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    } else if (isInserting) {
      context.missing(_authorMeta);
    }
    if (data.containsKey('body_text')) {
      context.handle(
        _bodyTextMeta,
        bodyText.isAcceptableOrUnknown(data['body_text']!, _bodyTextMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyTextMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    instanceId,
    profile,
    sessionId,
    messageId,
  };
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      instanceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instance_id'],
      )!,
      profile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      )!,
      bodyText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_text'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  Messages createAlias(String alias) {
    return Messages(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(instance_id, profile, session_id, message_id)',
    'FOREIGN KEY(instance_id, profile, session_id)REFERENCES sessions(instance_id, profile, session_id)ON DELETE CASCADE',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  final String instanceId;
  final String profile;
  final String sessionId;
  final String messageId;
  final String author;
  final String bodyText;

  /// Transcript row id: orders messages and matches `session.resume` ids.
  final int createdAt;
  const MessageRow({
    required this.instanceId,
    required this.profile,
    required this.sessionId,
    required this.messageId,
    required this.author,
    required this.bodyText,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['instance_id'] = Variable<String>(instanceId);
    map['profile'] = Variable<String>(profile);
    map['session_id'] = Variable<String>(sessionId);
    map['message_id'] = Variable<String>(messageId);
    map['author'] = Variable<String>(author);
    map['body_text'] = Variable<String>(bodyText);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      instanceId: Value(instanceId),
      profile: Value(profile),
      sessionId: Value(sessionId),
      messageId: Value(messageId),
      author: Value(author),
      bodyText: Value(bodyText),
      createdAt: Value(createdAt),
    );
  }

  factory MessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      instanceId: serializer.fromJson<String>(json['instance_id']),
      profile: serializer.fromJson<String>(json['profile']),
      sessionId: serializer.fromJson<String>(json['session_id']),
      messageId: serializer.fromJson<String>(json['message_id']),
      author: serializer.fromJson<String>(json['author']),
      bodyText: serializer.fromJson<String>(json['body_text']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'instance_id': serializer.toJson<String>(instanceId),
      'profile': serializer.toJson<String>(profile),
      'session_id': serializer.toJson<String>(sessionId),
      'message_id': serializer.toJson<String>(messageId),
      'author': serializer.toJson<String>(author),
      'body_text': serializer.toJson<String>(bodyText),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  MessageRow copyWith({
    String? instanceId,
    String? profile,
    String? sessionId,
    String? messageId,
    String? author,
    String? bodyText,
    int? createdAt,
  }) => MessageRow(
    instanceId: instanceId ?? this.instanceId,
    profile: profile ?? this.profile,
    sessionId: sessionId ?? this.sessionId,
    messageId: messageId ?? this.messageId,
    author: author ?? this.author,
    bodyText: bodyText ?? this.bodyText,
    createdAt: createdAt ?? this.createdAt,
  );
  MessageRow copyWithCompanion(MessagesCompanion data) {
    return MessageRow(
      instanceId: data.instanceId.present
          ? data.instanceId.value
          : this.instanceId,
      profile: data.profile.present ? data.profile.value : this.profile,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      author: data.author.present ? data.author.value : this.author,
      bodyText: data.bodyText.present ? data.bodyText.value : this.bodyText,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('instanceId: $instanceId, ')
          ..write('profile: $profile, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('author: $author, ')
          ..write('bodyText: $bodyText, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    instanceId,
    profile,
    sessionId,
    messageId,
    author,
    bodyText,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.instanceId == this.instanceId &&
          other.profile == this.profile &&
          other.sessionId == this.sessionId &&
          other.messageId == this.messageId &&
          other.author == this.author &&
          other.bodyText == this.bodyText &&
          other.createdAt == this.createdAt);
}

class MessagesCompanion extends UpdateCompanion<MessageRow> {
  final Value<String> instanceId;
  final Value<String> profile;
  final Value<String> sessionId;
  final Value<String> messageId;
  final Value<String> author;
  final Value<String> bodyText;
  final Value<int> createdAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.instanceId = const Value.absent(),
    this.profile = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.author = const Value.absent(),
    this.bodyText = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String instanceId,
    this.profile = const Value.absent(),
    required String sessionId,
    required String messageId,
    required String author,
    required String bodyText,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : instanceId = Value(instanceId),
       sessionId = Value(sessionId),
       messageId = Value(messageId),
       author = Value(author),
       bodyText = Value(bodyText),
       createdAt = Value(createdAt);
  static Insertable<MessageRow> custom({
    Expression<String>? instanceId,
    Expression<String>? profile,
    Expression<String>? sessionId,
    Expression<String>? messageId,
    Expression<String>? author,
    Expression<String>? bodyText,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (instanceId != null) 'instance_id': instanceId,
      if (profile != null) 'profile': profile,
      if (sessionId != null) 'session_id': sessionId,
      if (messageId != null) 'message_id': messageId,
      if (author != null) 'author': author,
      if (bodyText != null) 'body_text': bodyText,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? instanceId,
    Value<String>? profile,
    Value<String>? sessionId,
    Value<String>? messageId,
    Value<String>? author,
    Value<String>? bodyText,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      instanceId: instanceId ?? this.instanceId,
      profile: profile ?? this.profile,
      sessionId: sessionId ?? this.sessionId,
      messageId: messageId ?? this.messageId,
      author: author ?? this.author,
      bodyText: bodyText ?? this.bodyText,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (instanceId.present) {
      map['instance_id'] = Variable<String>(instanceId.value);
    }
    if (profile.present) {
      map['profile'] = Variable<String>(profile.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (bodyText.present) {
      map['body_text'] = Variable<String>(bodyText.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('instanceId: $instanceId, ')
          ..write('profile: $profile, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('author: $author, ')
          ..write('bodyText: $bodyText, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class MessagesFts extends Table
    with
        TableInfo<MessagesFts, MessagesFt>,
        VirtualTableInfo<MessagesFts, MessagesFt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MessagesFts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bodyTextMeta = const VerificationMeta(
    'bodyText',
  );
  late final GeneratedColumn<String> bodyText = GeneratedColumn<String>(
    'body_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [bodyText];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages_fts';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessagesFt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('body_text')) {
      context.handle(
        _bodyTextMeta,
        bodyText.isAcceptableOrUnknown(data['body_text']!, _bodyTextMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyTextMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  MessagesFt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessagesFt(
      bodyText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_text'],
      )!,
    );
  }

  @override
  MessagesFts createAlias(String alias) {
    return MessagesFts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs =>
      'fts5(body_text, content = \'messages\', content_rowid = \'rowid\')';
}

class MessagesFt extends DataClass implements Insertable<MessagesFt> {
  final String bodyText;
  const MessagesFt({required this.bodyText});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['body_text'] = Variable<String>(bodyText);
    return map;
  }

  MessagesFtsCompanion toCompanion(bool nullToAbsent) {
    return MessagesFtsCompanion(bodyText: Value(bodyText));
  }

  factory MessagesFt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessagesFt(bodyText: serializer.fromJson<String>(json['body_text']));
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'body_text': serializer.toJson<String>(bodyText)};
  }

  MessagesFt copyWith({String? bodyText}) =>
      MessagesFt(bodyText: bodyText ?? this.bodyText);
  MessagesFt copyWithCompanion(MessagesFtsCompanion data) {
    return MessagesFt(
      bodyText: data.bodyText.present ? data.bodyText.value : this.bodyText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessagesFt(')
          ..write('bodyText: $bodyText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => bodyText.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessagesFt && other.bodyText == this.bodyText);
}

class MessagesFtsCompanion extends UpdateCompanion<MessagesFt> {
  final Value<String> bodyText;
  final Value<int> rowid;
  const MessagesFtsCompanion({
    this.bodyText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesFtsCompanion.insert({
    required String bodyText,
    this.rowid = const Value.absent(),
  }) : bodyText = Value(bodyText);
  static Insertable<MessagesFt> custom({
    Expression<String>? bodyText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bodyText != null) 'body_text': bodyText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesFtsCompanion copyWith({Value<String>? bodyText, Value<int>? rowid}) {
    return MessagesFtsCompanion(
      bodyText: bodyText ?? this.bodyText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bodyText.present) {
      map['body_text'] = Variable<String>(bodyText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesFtsCompanion(')
          ..write('bodyText: $bodyText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Settings extends Table with TableInfo<Settings, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Settings(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  Settings createAlias(String alias) {
    return Settings(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$HermuseDatabase extends GeneratedDatabase {
  _$HermuseDatabase(QueryExecutor e) : super(e);
  $HermuseDatabaseManager get managers => $HermuseDatabaseManager(this);
  late final Instances instances = Instances(this);
  late final Sessions sessions = Sessions(this);
  late final Messages messages = Messages(this);
  late final MessagesFts messagesFts = MessagesFts(this);
  late final Trigger messagesFtsInsert = Trigger(
    'CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN INSERT INTO messages_fts ("rowid", body_text) VALUES (new."rowid", new.body_text);END',
    'messages_fts_insert',
  );
  late final Trigger messagesFtsDelete = Trigger(
    'CREATE TRIGGER messages_fts_delete AFTER DELETE ON messages BEGIN INSERT INTO messages_fts (messages_fts, "rowid", body_text) VALUES (\'delete\', old."rowid", old.body_text);END',
    'messages_fts_delete',
  );
  late final Trigger messagesFtsUpdate = Trigger(
    'CREATE TRIGGER messages_fts_update AFTER UPDATE ON messages BEGIN INSERT INTO messages_fts (messages_fts, "rowid", body_text) VALUES (\'delete\', old."rowid", old.body_text);INSERT INTO messages_fts ("rowid", body_text) VALUES (new."rowid", new.body_text);END',
    'messages_fts_update',
  );
  late final Settings settings = Settings(this);
  Selectable<SearchMessagesResult> searchMessages(
    String query,
    String instanceId,
    String profile,
    List<String> sessionIds,
    int limit,
  ) {
    var $arrayStartIndex = 5;
    final expandedsessionIds = $expandVar($arrayStartIndex, sessionIds.length);
    $arrayStartIndex += sessionIds.length;
    return customSelect(
      'SELECT"m"."instance_id" AS "nested_0.instance_id", "m"."profile" AS "nested_0.profile", "m"."session_id" AS "nested_0.session_id", "m"."message_id" AS "nested_0.message_id", "m"."author" AS "nested_0.author", "m"."body_text" AS "nested_0.body_text", "m"."created_at" AS "nested_0.created_at" FROM messages_fts AS f INNER JOIN messages AS m ON m."rowid" = f."rowid" WHERE messages_fts MATCH ?1 AND m.instance_id = ?2 AND m.profile = ?3 AND m.session_id IN ($expandedsessionIds) ORDER BY rank LIMIT ?4',
      variables: [
        Variable<String>(query),
        Variable<String>(instanceId),
        Variable<String>(profile),
        Variable<int>(limit),
        for (var $ in sessionIds) Variable<String>($),
      ],
      readsFrom: {this.messagesFts, this.messages},
    ).asyncMap(
      (QueryRow row) async => SearchMessagesResult(
        m: await this.messages.mapFromRow(row, tablePrefix: 'nested_0'),
      ),
    );
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    instances,
    sessions,
    messages,
    messagesFts,
    messagesFtsInsert,
    messagesFtsDelete,
    messagesFtsUpdate,
    settings,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'instances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sessions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('messages_fts', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages_fts', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [TableUpdate('messages_fts', kind: UpdateKind.insert)],
    ),
  ]);
}

typedef $InstancesCreateCompanionBuilder = InstancesCompanion Function({
  required String id,
  required String label,
  required String kind,
  required String baseUrl,
  required String auth,
  Value<String?> profile,
  Value<bool> isPrimary,
  required int position,
  Value<int> rowid,
});
typedef $InstancesUpdateCompanionBuilder = InstancesCompanion Function({
  Value<String> id,
  Value<String> label,
  Value<String> kind,
  Value<String> baseUrl,
  Value<String> auth,
  Value<String?> profile,
  Value<bool> isPrimary,
  Value<int> position,
  Value<int> rowid,
});

final class $InstancesReferences
    extends BaseReferences<_$HermuseDatabase, Instances, InstanceRow> {
  $InstancesReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<Sessions, List<SessionRow>> _sessionsRefsTable(
    _$HermuseDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.sessions,
    aliasName: 'instances__id__sessions__instance_id',
  );

  $SessionsProcessedTableManager get sessionsRefs {
    final manager = $SessionsTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.instanceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $InstancesFilterComposer extends Composer<_$HermuseDatabase, Instances> {
  $InstancesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get auth => $composableBuilder(
    column: $table.auth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> sessionsRefs(
    Expression<bool> Function($SessionsFilterComposer f) f,
  ) {
    final $SessionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.instanceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SessionsFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $InstancesOrderingComposer
    extends Composer<_$HermuseDatabase, Instances> {
  $InstancesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get auth => $composableBuilder(
    column: $table.auth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $InstancesAnnotationComposer
    extends Composer<_$HermuseDatabase, Instances> {
  $InstancesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get auth =>
      $composableBuilder(column: $table.auth, builder: (column) => column);

  GeneratedColumn<String> get profile =>
      $composableBuilder(column: $table.profile, builder: (column) => column);

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  Expression<T> sessionsRefs<T extends Object>(
    Expression<T> Function($SessionsAnnotationComposer a) f,
  ) {
    final $SessionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.instanceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SessionsAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $InstancesTableManager
    extends
        RootTableManager<
          _$HermuseDatabase,
          Instances,
          InstanceRow,
          $InstancesFilterComposer,
          $InstancesOrderingComposer,
          $InstancesAnnotationComposer,
          $InstancesCreateCompanionBuilder,
          $InstancesUpdateCompanionBuilder,
          (InstanceRow, $InstancesReferences),
          InstanceRow,
          PrefetchHooks Function({bool sessionsRefs})
        > {
  $InstancesTableManager(_$HermuseDatabase db, Instances table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $InstancesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $InstancesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $InstancesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<String> auth = const Value.absent(),
                Value<String?> profile = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstancesCompanion(
                id: id,
                label: label,
                kind: kind,
                baseUrl: baseUrl,
                auth: auth,
                profile: profile,
                isPrimary: isPrimary,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String label,
                required String kind,
                required String baseUrl,
                required String auth,
                Value<String?> profile = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => InstancesCompanion.insert(
                id: id,
                label: label,
                kind: kind,
                baseUrl: baseUrl,
                auth: auth,
                profile: profile,
                isPrimary: isPrimary,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Instances, InstanceRow>(table),
                  $InstancesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (sessionsRefs) db.sessions],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (sessionsRefs)
                    await $_getPrefetchedData<
                      InstanceRow,
                      Instances,
                      SessionRow
                    >(
                      currentTable: table,
                      referencedTable: $InstancesReferences._sessionsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $InstancesReferences(db, table, p0).sessionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.instanceId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $InstancesProcessedTableManager =
    ProcessedTableManager<
      _$HermuseDatabase,
      Instances,
      InstanceRow,
      $InstancesFilterComposer,
      $InstancesOrderingComposer,
      $InstancesAnnotationComposer,
      $InstancesCreateCompanionBuilder,
      $InstancesUpdateCompanionBuilder,
      (InstanceRow, $InstancesReferences),
      InstanceRow,
      PrefetchHooks Function({bool sessionsRefs})
    >;
typedef $SessionsCreateCompanionBuilder = SessionsCompanion Function({
  required String instanceId,
  Value<String> profile,
  required String sessionId,
  Value<String> title,
  Value<String?> parentId,
  required int updatedAt,
  Value<bool> archived,
  Value<int?> pinnedAt,
  Value<int> rowid,
});
typedef $SessionsUpdateCompanionBuilder = SessionsCompanion Function({
  Value<String> instanceId,
  Value<String> profile,
  Value<String> sessionId,
  Value<String> title,
  Value<String?> parentId,
  Value<int> updatedAt,
  Value<bool> archived,
  Value<int?> pinnedAt,
  Value<int> rowid,
});

final class $SessionsReferences
    extends BaseReferences<_$HermuseDatabase, Sessions, SessionRow> {
  $SessionsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Instances _instanceIdTable(_$HermuseDatabase db) =>
      db.instances.createAlias('sessions__instance_id__instances__id');

  $InstancesProcessedTableManager get instanceId {
    final $_column = $_itemColumn<String>('instance_id')!;

    final manager = $InstancesTableManager(
      $_db,
      $_db.instances,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_instanceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $SessionsFilterComposer extends Composer<_$HermuseDatabase, Sessions> {
  $SessionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnFilters(column),
  );

  $InstancesFilterComposer get instanceId {
    final $InstancesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.instanceId,
      referencedTable: $db.instances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $InstancesFilterComposer(
            $db: $db,
            $table: $db.instances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SessionsOrderingComposer extends Composer<_$HermuseDatabase, Sessions> {
  $SessionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $InstancesOrderingComposer get instanceId {
    final $InstancesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.instanceId,
      referencedTable: $db.instances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $InstancesOrderingComposer(
            $db: $db,
            $table: $db.instances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SessionsAnnotationComposer
    extends Composer<_$HermuseDatabase, Sessions> {
  $SessionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profile =>
      $composableBuilder(column: $table.profile, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<int> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);

  $InstancesAnnotationComposer get instanceId {
    final $InstancesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.instanceId,
      referencedTable: $db.instances,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $InstancesAnnotationComposer(
            $db: $db,
            $table: $db.instances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SessionsTableManager
    extends
        RootTableManager<
          _$HermuseDatabase,
          Sessions,
          SessionRow,
          $SessionsFilterComposer,
          $SessionsOrderingComposer,
          $SessionsAnnotationComposer,
          $SessionsCreateCompanionBuilder,
          $SessionsUpdateCompanionBuilder,
          (SessionRow, $SessionsReferences),
          SessionRow,
          PrefetchHooks Function({bool instanceId})
        > {
  $SessionsTableManager(_$HermuseDatabase db, Sessions table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SessionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SessionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SessionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> instanceId = const Value.absent(),
                Value<String> profile = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<int?> pinnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                instanceId: instanceId,
                profile: profile,
                sessionId: sessionId,
                title: title,
                parentId: parentId,
                updatedAt: updatedAt,
                archived: archived,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String instanceId,
                Value<String> profile = const Value.absent(),
                required String sessionId,
                Value<String> title = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                required int updatedAt,
                Value<bool> archived = const Value.absent(),
                Value<int?> pinnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                instanceId: instanceId,
                profile: profile,
                sessionId: sessionId,
                title: title,
                parentId: parentId,
                updatedAt: updatedAt,
                archived: archived,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Sessions, SessionRow>(table),
                  $SessionsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({instanceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (instanceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.instanceId,
                        referencedTable: $SessionsReferences._instanceIdTable(
                          db,
                        ),
                        referencedColumn: $SessionsReferences
                            ._instanceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $SessionsProcessedTableManager =
    ProcessedTableManager<
      _$HermuseDatabase,
      Sessions,
      SessionRow,
      $SessionsFilterComposer,
      $SessionsOrderingComposer,
      $SessionsAnnotationComposer,
      $SessionsCreateCompanionBuilder,
      $SessionsUpdateCompanionBuilder,
      (SessionRow, $SessionsReferences),
      SessionRow,
      PrefetchHooks Function({bool instanceId})
    >;
typedef $MessagesCreateCompanionBuilder = MessagesCompanion Function({
  required String instanceId,
  Value<String> profile,
  required String sessionId,
  required String messageId,
  required String author,
  required String bodyText,
  required int createdAt,
  Value<int> rowid,
});
typedef $MessagesUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> instanceId,
  Value<String> profile,
  Value<String> sessionId,
  Value<String> messageId,
  Value<String> author,
  Value<String> bodyText,
  Value<int> createdAt,
  Value<int> rowid,
});

class $MessagesFilterComposer extends Composer<_$HermuseDatabase, Messages> {
  $MessagesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyText => $composableBuilder(
    column: $table.bodyText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $MessagesOrderingComposer extends Composer<_$HermuseDatabase, Messages> {
  $MessagesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyText => $composableBuilder(
    column: $table.bodyText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $MessagesAnnotationComposer
    extends Composer<_$HermuseDatabase, Messages> {
  $MessagesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get profile =>
      $composableBuilder(column: $table.profile, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get bodyText =>
      $composableBuilder(column: $table.bodyText, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $MessagesTableManager
    extends
        RootTableManager<
          _$HermuseDatabase,
          Messages,
          MessageRow,
          $MessagesFilterComposer,
          $MessagesOrderingComposer,
          $MessagesAnnotationComposer,
          $MessagesCreateCompanionBuilder,
          $MessagesUpdateCompanionBuilder,
          (MessageRow, BaseReferences<_$HermuseDatabase, Messages, MessageRow>),
          MessageRow,
          PrefetchHooks Function()
        > {
  $MessagesTableManager(_$HermuseDatabase db, Messages table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MessagesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MessagesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MessagesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> instanceId = const Value.absent(),
                Value<String> profile = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<String> bodyText = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                instanceId: instanceId,
                profile: profile,
                sessionId: sessionId,
                messageId: messageId,
                author: author,
                bodyText: bodyText,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String instanceId,
                Value<String> profile = const Value.absent(),
                required String sessionId,
                required String messageId,
                required String author,
                required String bodyText,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                instanceId: instanceId,
                profile: profile,
                sessionId: sessionId,
                messageId: messageId,
                author: author,
                bodyText: bodyText,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Messages, MessageRow>(table),
                  BaseReferences<_$HermuseDatabase, Messages, MessageRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $MessagesProcessedTableManager =
    ProcessedTableManager<
      _$HermuseDatabase,
      Messages,
      MessageRow,
      $MessagesFilterComposer,
      $MessagesOrderingComposer,
      $MessagesAnnotationComposer,
      $MessagesCreateCompanionBuilder,
      $MessagesUpdateCompanionBuilder,
      (MessageRow, BaseReferences<_$HermuseDatabase, Messages, MessageRow>),
      MessageRow,
      PrefetchHooks Function()
    >;
typedef $MessagesFtsCreateCompanionBuilder = MessagesFtsCompanion Function({
  required String bodyText,
  Value<int> rowid,
});
typedef $MessagesFtsUpdateCompanionBuilder = MessagesFtsCompanion Function({
  Value<String> bodyText,
  Value<int> rowid,
});

class $MessagesFtsFilterComposer
    extends Composer<_$HermuseDatabase, MessagesFts> {
  $MessagesFtsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bodyText => $composableBuilder(
    column: $table.bodyText,
    builder: (column) => ColumnFilters(column),
  );
}

class $MessagesFtsOrderingComposer
    extends Composer<_$HermuseDatabase, MessagesFts> {
  $MessagesFtsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bodyText => $composableBuilder(
    column: $table.bodyText,
    builder: (column) => ColumnOrderings(column),
  );
}

class $MessagesFtsAnnotationComposer
    extends Composer<_$HermuseDatabase, MessagesFts> {
  $MessagesFtsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bodyText =>
      $composableBuilder(column: $table.bodyText, builder: (column) => column);
}

class $MessagesFtsTableManager
    extends
        RootTableManager<
          _$HermuseDatabase,
          MessagesFts,
          MessagesFt,
          $MessagesFtsFilterComposer,
          $MessagesFtsOrderingComposer,
          $MessagesFtsAnnotationComposer,
          $MessagesFtsCreateCompanionBuilder,
          $MessagesFtsUpdateCompanionBuilder,
          (
            MessagesFt,
            BaseReferences<_$HermuseDatabase, MessagesFts, MessagesFt>,
          ),
          MessagesFt,
          PrefetchHooks Function()
        > {
  $MessagesFtsTableManager(_$HermuseDatabase db, MessagesFts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MessagesFtsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MessagesFtsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MessagesFtsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> bodyText = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => MessagesFtsCompanion(bodyText: bodyText, rowid: rowid),
          createCompanionCallback: ({
            required String bodyText,
            Value<int> rowid = const Value.absent(),
          }) => MessagesFtsCompanion.insert(bodyText: bodyText, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<MessagesFts, MessagesFt>(table),
                  BaseReferences<_$HermuseDatabase, MessagesFts, MessagesFt>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $MessagesFtsProcessedTableManager =
    ProcessedTableManager<
      _$HermuseDatabase,
      MessagesFts,
      MessagesFt,
      $MessagesFtsFilterComposer,
      $MessagesFtsOrderingComposer,
      $MessagesFtsAnnotationComposer,
      $MessagesFtsCreateCompanionBuilder,
      $MessagesFtsUpdateCompanionBuilder,
      (MessagesFt, BaseReferences<_$HermuseDatabase, MessagesFts, MessagesFt>),
      MessagesFt,
      PrefetchHooks Function()
    >;
typedef $SettingsCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $SettingsUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $SettingsFilterComposer extends Composer<_$HermuseDatabase, Settings> {
  $SettingsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $SettingsOrderingComposer extends Composer<_$HermuseDatabase, Settings> {
  $SettingsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $SettingsAnnotationComposer
    extends Composer<_$HermuseDatabase, Settings> {
  $SettingsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $SettingsTableManager
    extends
        RootTableManager<
          _$HermuseDatabase,
          Settings,
          SettingRow,
          $SettingsFilterComposer,
          $SettingsOrderingComposer,
          $SettingsAnnotationComposer,
          $SettingsCreateCompanionBuilder,
          $SettingsUpdateCompanionBuilder,
          (SettingRow, BaseReferences<_$HermuseDatabase, Settings, SettingRow>),
          SettingRow,
          PrefetchHooks Function()
        > {
  $SettingsTableManager(_$HermuseDatabase db, Settings table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SettingsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SettingsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SettingsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Settings, SettingRow>(table),
                  BaseReferences<_$HermuseDatabase, Settings, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $SettingsProcessedTableManager =
    ProcessedTableManager<
      _$HermuseDatabase,
      Settings,
      SettingRow,
      $SettingsFilterComposer,
      $SettingsOrderingComposer,
      $SettingsAnnotationComposer,
      $SettingsCreateCompanionBuilder,
      $SettingsUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$HermuseDatabase, Settings, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $HermuseDatabaseManager {
  final _$HermuseDatabase _db;
  $HermuseDatabaseManager(this._db);
  $InstancesTableManager get instances =>
      $InstancesTableManager(_db, _db.instances);
  $SessionsTableManager get sessions =>
      $SessionsTableManager(_db, _db.sessions);
  $MessagesTableManager get messages =>
      $MessagesTableManager(_db, _db.messages);
  $MessagesFtsTableManager get messagesFts =>
      $MessagesFtsTableManager(_db, _db.messagesFts);
  $SettingsTableManager get settings =>
      $SettingsTableManager(_db, _db.settings);
}

class SearchMessagesResult {
  final MessageRow m;
  SearchMessagesResult({required this.m});
}
