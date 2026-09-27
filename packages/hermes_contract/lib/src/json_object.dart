/// A generated contract object that serialises to a JSON object.
abstract interface class JsonObject {
  /// The JSON object sent on the wire. Only keys of the contract are emitted.
  Map<String, Object?> toJson();
}
