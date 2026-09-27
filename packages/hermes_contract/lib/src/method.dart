import 'json_object.dart';

/// A typed client → server JSON-RPC method.
final class HermesMethod<P extends JsonObject, R extends Object> {
  const HermesMethod(this.name, this._decode);

  /// Wire method name, e.g. `prompt.submit`.
  final String name;
  final R Function(Map<String, Object?> json) _decode;

  /// Decodes the JSON-RPC `result` member.
  R decodeResult(Object? json) => _decode(
    json is Map<String, Object?>
        ? json
        : throw FormatException('$name: result is not an object: $json'),
  );
}
