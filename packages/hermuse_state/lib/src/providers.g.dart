// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's database. Must be overridden (`openNativeDatabase` on Flutter,
/// `openWebDatabase` on the web).

@ProviderFor(hermuseDatabase)
final hermuseDatabaseProvider = HermuseDatabaseProvider._();

/// The app's database. Must be overridden (`openNativeDatabase` on Flutter,
/// `openWebDatabase` on the web).

final class HermuseDatabaseProvider
    extends
        $FunctionalProvider<HermuseDatabase, HermuseDatabase, HermuseDatabase>
    with $Provider<HermuseDatabase> {
  /// The app's database. Must be overridden (`openNativeDatabase` on Flutter,
  /// `openWebDatabase` on the web).
  HermuseDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hermuseDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hermuseDatabaseHash();

  @$internal
  @override
  $ProviderElement<HermuseDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HermuseDatabase create(Ref ref) {
    return hermuseDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HermuseDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HermuseDatabase>(value),
    );
  }
}

String _$hermuseDatabaseHash() => r'ef28a48faf31e1569e2ac468c9774c2752b8e1ef';

/// Platform secret storage. Must be overridden (keystore on Flutter,
/// `MemorySecretStore` on the web).

@ProviderFor(secretStore)
final secretStoreProvider = SecretStoreProvider._();

/// Platform secret storage. Must be overridden (keystore on Flutter,
/// `MemorySecretStore` on the web).

final class SecretStoreProvider
    extends $FunctionalProvider<SecretStore, SecretStore, SecretStore>
    with $Provider<SecretStore> {
  /// Platform secret storage. Must be overridden (keystore on Flutter,
  /// `MemorySecretStore` on the web).
  SecretStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'secretStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$secretStoreHash();

  @$internal
  @override
  $ProviderElement<SecretStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SecretStore create(Ref ref) {
    return secretStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SecretStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SecretStore>(value),
    );
  }
}

String _$secretStoreHash() => r'83f83fe687d33e8d435f066e8b6b4e957ba30c36';

@ProviderFor(httpClient)
final httpClientProvider = HttpClientProvider._();

final class HttpClientProvider
    extends $FunctionalProvider<http.Client, http.Client, http.Client>
    with $Provider<http.Client> {
  HttpClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'httpClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$httpClientHash();

  @$internal
  @override
  $ProviderElement<http.Client> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  http.Client create(Ref ref) {
    return httpClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(http.Client value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<http.Client>(value),
    );
  }
}

String _$httpClientHash() => r'7ec49beae0f15115de79f9aa98dbd250130e26d8';

@ProviderFor(transportFactory)
final transportFactoryProvider = TransportFactoryProvider._();

final class TransportFactoryProvider
    extends
        $FunctionalProvider<
          TransportFactory,
          TransportFactory,
          TransportFactory
        >
    with $Provider<TransportFactory> {
  TransportFactoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transportFactoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transportFactoryHash();

  @$internal
  @override
  $ProviderElement<TransportFactory> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TransportFactory create(Ref ref) {
    return transportFactory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TransportFactory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TransportFactory>(value),
    );
  }
}

String _$transportFactoryHash() => r'ecaec1710337608ecccb84858ea621d4c8238df3';

/// The instance registry, loaded from the database.

@ProviderFor(registry)
final registryProvider = RegistryProvider._();

/// The instance registry, loaded from the database.

final class RegistryProvider
    extends
        $FunctionalProvider<
          AsyncValue<HermesRegistry>,
          HermesRegistry,
          FutureOr<HermesRegistry>
        >
    with $FutureModifier<HermesRegistry>, $FutureProvider<HermesRegistry> {
  /// The instance registry, loaded from the database.
  RegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'registryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$registryHash();

  @$internal
  @override
  $FutureProviderElement<HermesRegistry> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<HermesRegistry> create(Ref ref) {
    return registry(ref);
  }
}

String _$registryHash() => r'7522359db08eb5905b94125c18c8f65f06fca67a';

/// Overridden in widget tests, where no real socket can open.

@ProviderFor(trialConnect)
final trialConnectProvider = TrialConnectProvider._();

/// Overridden in widget tests, where no real socket can open.

final class TrialConnectProvider
    extends $FunctionalProvider<TrialConnect, TrialConnect, TrialConnect>
    with $Provider<TrialConnect> {
  /// Overridden in widget tests, where no real socket can open.
  TrialConnectProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trialConnectProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trialConnectHash();

  @$internal
  @override
  $ProviderElement<TrialConnect> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TrialConnect create(Ref ref) {
    return trialConnect(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TrialConnect value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TrialConnect>(value),
    );
  }
}

String _$trialConnectHash() => r'48bf95a9b6dfb4e45065c1051136fb0b33f3a2b0';

/// Credential maintenance for registered instances.

@ProviderFor(instanceAuth)
final instanceAuthProvider = InstanceAuthProvider._();

/// Credential maintenance for registered instances.

final class InstanceAuthProvider
    extends $FunctionalProvider<InstanceAuth, InstanceAuth, InstanceAuth>
    with $Provider<InstanceAuth> {
  /// Credential maintenance for registered instances.
  InstanceAuthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'instanceAuthProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$instanceAuthHash();

  @$internal
  @override
  $ProviderElement<InstanceAuth> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  InstanceAuth create(Ref ref) {
    return instanceAuth(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(InstanceAuth value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<InstanceAuth>(value),
    );
  }
}

String _$instanceAuthHash() => r'863be96fa90a7d6882260d25c5c5ce9486747190';

/// Registered instances, in user order.

@ProviderFor(instances)
final instancesProvider = InstancesProvider._();

/// Registered instances, in user order.

final class InstancesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<HermesInstance>>,
          List<HermesInstance>,
          Stream<List<HermesInstance>>
        >
    with
        $FutureModifier<List<HermesInstance>>,
        $StreamProvider<List<HermesInstance>> {
  /// Registered instances, in user order.
  InstancesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'instancesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$instancesHash();

  @$internal
  @override
  $StreamProviderElement<List<HermesInstance>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<HermesInstance>> create(Ref ref) {
    return instances(ref);
  }
}

String _$instancesHash() => r'27bad291a19f093439948cf74be988ac7792fab0';

/// A profile's separate connection, opened lazily and closed
/// [connectionLinger] after its last listener goes away. Credentials remain
/// keyed by the real registered instance id.

@ProviderFor(connection)
final connectionProvider = ConnectionFamily._();

/// A profile's separate connection, opened lazily and closed
/// [connectionLinger] after its last listener goes away. Credentials remain
/// keyed by the real registered instance id.

final class ConnectionProvider
    extends
        $FunctionalProvider<
          AsyncValue<HermesConnection>,
          HermesConnection,
          FutureOr<HermesConnection>
        >
    with $FutureModifier<HermesConnection>, $FutureProvider<HermesConnection> {
  /// A profile's separate connection, opened lazily and closed
  /// [connectionLinger] after its last listener goes away. Credentials remain
  /// keyed by the real registered instance id.
  ConnectionProvider._({
    required ConnectionFamily super.from,
    required (String, {String profile}) super.argument,
  }) : super(
         retry: _noRetry,
         name: r'connectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$connectionHash();

  @override
  String toString() {
    return r'connectionProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<HermesConnection> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<HermesConnection> create(Ref ref) {
    final argument = this.argument as (String, {String profile});
    return connection(ref, argument.$1, profile: argument.profile);
  }

  @override
  bool operator ==(Object other) {
    return other is ConnectionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$connectionHash() => r'78d0db21300eccf3c1f78181289861a27442a661';

/// A profile's separate connection, opened lazily and closed
/// [connectionLinger] after its last listener goes away. Credentials remain
/// keyed by the real registered instance id.

final class ConnectionFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<HermesConnection>,
          (String, {String profile})
        > {
  ConnectionFamily._()
    : super(
        retry: _noRetry,
        name: r'connectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A profile's separate connection, opened lazily and closed
  /// [connectionLinger] after its last listener goes away. Credentials remain
  /// keyed by the real registered instance id.

  ConnectionProvider call(String instanceId, {String profile = 'default'}) =>
      ConnectionProvider._(
        argument: (instanceId, profile: profile),
        from: this,
      );

  @override
  String toString() => r'connectionProvider';
}

/// Live [ConnectionState] of an instance (drives status badges).

@ProviderFor(connectionState)
final connectionStateProvider = ConnectionStateFamily._();

/// Live [ConnectionState] of an instance (drives status badges).

final class ConnectionStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConnectionState>,
          ConnectionState,
          Stream<ConnectionState>
        >
    with $FutureModifier<ConnectionState>, $StreamProvider<ConnectionState> {
  /// Live [ConnectionState] of an instance (drives status badges).
  ConnectionStateProvider._({
    required ConnectionStateFamily super.from,
    required (String, {String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'connectionStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$connectionStateHash();

  @override
  String toString() {
    return r'connectionStateProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<ConnectionState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConnectionState> create(Ref ref) {
    final argument = this.argument as (String, {String profile});
    return connectionState(ref, argument.$1, profile: argument.profile);
  }

  @override
  bool operator ==(Object other) {
    return other is ConnectionStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$connectionStateHash() => r'90d7661145ca30dbb081aceae450679f194f989b';

/// Live [ConnectionState] of an instance (drives status badges).

final class ConnectionStateFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<ConnectionState>,
          (String, {String profile})
        > {
  ConnectionStateFamily._()
    : super(
        retry: null,
        name: r'connectionStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Live [ConnectionState] of an instance (drives status badges).

  ConnectionStateProvider call(
    String instanceId, {
    String profile = 'default',
  }) => ConnectionStateProvider._(
    argument: (instanceId, profile: profile),
    from: this,
  );

  @override
  String toString() => r'connectionStateProvider';
}

/// The selected agent's main chat, persisted across launches. An uncreated
/// main chat keeps its draft provider key while its stored id is saved.

@ProviderFor(ActiveThread)
final activeThreadProvider = ActiveThreadProvider._();

/// The selected agent's main chat, persisted across launches. An uncreated
/// main chat keeps its draft provider key while its stored id is saved.
final class ActiveThreadProvider
    extends $AsyncNotifierProvider<ActiveThread, ThreadRef?> {
  /// The selected agent's main chat, persisted across launches. An uncreated
  /// main chat keeps its draft provider key while its stored id is saved.
  ActiveThreadProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeThreadProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeThreadHash();

  @$internal
  @override
  ActiveThread create() => ActiveThread();
}

String _$activeThreadHash() => r'5ef6c12e8c37c1d8ba0b6ea176161b4199255e27';

/// The selected agent's main chat, persisted across launches. An uncreated
/// main chat keeps its draft provider key while its stored id is saved.

abstract class _$ActiveThread extends $AsyncNotifier<ThreadRef?> {
  FutureOr<ThreadRef?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ThreadRef?>, ThreadRef?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ThreadRef?>, ThreadRef?>,
              AsyncValue<ThreadRef?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The chat of the main session [thread] (main chat + its side chats),
/// opened on the thread that was on screen last time.

@ProviderFor(chatSession)
final chatSessionProvider = ChatSessionFamily._();

/// The chat of the main session [thread] (main chat + its side chats),
/// opened on the thread that was on screen last time.

final class ChatSessionProvider
    extends
        $FunctionalProvider<
          AsyncValue<ChatController>,
          ChatController,
          FutureOr<ChatController>
        >
    with $FutureModifier<ChatController>, $FutureProvider<ChatController> {
  /// The chat of the main session [thread] (main chat + its side chats),
  /// opened on the thread that was on screen last time.
  ChatSessionProvider._({
    required ChatSessionFamily super.from,
    required ThreadRef super.argument,
  }) : super(
         retry: null,
         name: r'chatSessionProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatSessionHash();

  @override
  String toString() {
    return r'chatSessionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ChatController> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ChatController> create(Ref ref) {
    final argument = this.argument as ThreadRef;
    return chatSession(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatSessionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatSessionHash() => r'7d5f0f799c9be26264f65e616bc1b0b86e57b66b';

/// The chat of the main session [thread] (main chat + its side chats),
/// opened on the thread that was on screen last time.

final class ChatSessionFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ChatController>, ThreadRef> {
  ChatSessionFamily._()
    : super(
        retry: null,
        name: r'chatSessionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The chat of the main session [thread] (main chat + its side chats),
  /// opened on the thread that was on screen last time.

  ChatSessionProvider call(ThreadRef thread) =>
      ChatSessionProvider._(argument: thread, from: this);

  @override
  String toString() => r'chatSessionProvider';
}

/// Side chats of the main chat [main] as stored locally (pin and activity
/// order); empty until the main chat exists. [archived] lists the archive.

@ProviderFor(sideChats)
final sideChatsProvider = SideChatsFamily._();

/// Side chats of the main chat [main] as stored locally (pin and activity
/// order); empty until the main chat exists. [archived] lists the archive.

final class SideChatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SessionRow>>,
          List<SessionRow>,
          Stream<List<SessionRow>>
        >
    with $FutureModifier<List<SessionRow>>, $StreamProvider<List<SessionRow>> {
  /// Side chats of the main chat [main] as stored locally (pin and activity
  /// order); empty until the main chat exists. [archived] lists the archive.
  SideChatsProvider._({
    required SideChatsFamily super.from,
    required (ThreadRef, {bool archived}) super.argument,
  }) : super(
         retry: null,
         name: r'sideChatsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sideChatsHash();

  @override
  String toString() {
    return r'sideChatsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<SessionRow>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<SessionRow>> create(Ref ref) {
    final argument = this.argument as (ThreadRef, {bool archived});
    return sideChats(ref, argument.$1, archived: argument.archived);
  }

  @override
  bool operator ==(Object other) {
    return other is SideChatsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sideChatsHash() => r'882a662e2c8887f5fa265bfc40cdd946d484943c';

/// Side chats of the main chat [main] as stored locally (pin and activity
/// order); empty until the main chat exists. [archived] lists the archive.

final class SideChatsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<SessionRow>>,
          (ThreadRef, {bool archived})
        > {
  SideChatsFamily._()
    : super(
        retry: null,
        name: r'sideChatsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Side chats of the main chat [main] as stored locally (pin and activity
  /// order); empty until the main chat exists. [archived] lists the archive.

  SideChatsProvider call(ThreadRef main, {bool archived = false}) =>
      SideChatsProvider._(argument: (main, archived: archived), from: this);

  @override
  String toString() => r'sideChatsProvider';
}

/// Last activity of the main chat [main] (null until it exists).

@ProviderFor(mainChatUpdatedAt)
final mainChatUpdatedAtProvider = MainChatUpdatedAtFamily._();

/// Last activity of the main chat [main] (null until it exists).

final class MainChatUpdatedAtProvider
    extends
        $FunctionalProvider<AsyncValue<DateTime?>, DateTime?, Stream<DateTime?>>
    with $FutureModifier<DateTime?>, $StreamProvider<DateTime?> {
  /// Last activity of the main chat [main] (null until it exists).
  MainChatUpdatedAtProvider._({
    required MainChatUpdatedAtFamily super.from,
    required ThreadRef super.argument,
  }) : super(
         retry: null,
         name: r'mainChatUpdatedAtProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mainChatUpdatedAtHash();

  @override
  String toString() {
    return r'mainChatUpdatedAtProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<DateTime?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<DateTime?> create(Ref ref) {
    final argument = this.argument as ThreadRef;
    return mainChatUpdatedAt(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MainChatUpdatedAtProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mainChatUpdatedAtHash() => r'd4329d66507889dfe591de02d43f18b0afb51ac8';

/// Last activity of the main chat [main] (null until it exists).

final class MainChatUpdatedAtFamily extends $Family
    with $FunctionalFamilyOverride<Stream<DateTime?>, ThreadRef> {
  MainChatUpdatedAtFamily._()
    : super(
        retry: null,
        name: r'mainChatUpdatedAtProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Last activity of the main chat [main] (null until it exists).

  MainChatUpdatedAtProvider call(ThreadRef main) =>
      MainChatUpdatedAtProvider._(argument: main, from: this);

  @override
  String toString() => r'mainChatUpdatedAtProvider';
}

@ProviderFor(ChatPanel)
final chatPanelProvider = ChatPanelProvider._();

final class ChatPanelProvider
    extends $AsyncNotifierProvider<ChatPanel, ChatPanelPrefs> {
  ChatPanelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatPanelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatPanelHash();

  @$internal
  @override
  ChatPanel create() => ChatPanel();
}

String _$chatPanelHash() => r'efc5353d51e3e5b01fa0b015ccecb597c31dcffa';

abstract class _$ChatPanel extends $AsyncNotifier<ChatPanelPrefs> {
  FutureOr<ChatPanelPrefs> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ChatPanelPrefs>, ChatPanelPrefs>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ChatPanelPrefs>, ChatPanelPrefs>,
              AsyncValue<ChatPanelPrefs>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
