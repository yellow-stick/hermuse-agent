import 'package:hermuse_web/relay.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('Relay.detect', () {
    final page = Uri.parse('https://chat.example.com/some/route?x=1');

    test(
      'a relay answering /relay/health on the page origin is used',
      () async {
        Uri? asked;
        final relay = await Relay.detect(
          MockClient((request) async {
            asked = request.url;
            return http.Response('{"ok":true}', 200);
          }),
          page,
        );
        expect(asked, Uri.parse('https://chat.example.com/relay/health'));
        expect(relay, Uri.parse('https://chat.example.com'));
      },
    );

    test('a plain static server means no relay', () async {
      for (final response in [
        http.Response('not found', 404),
        http.Response('<!doctype html>', 200), // SPA fallback page
        http.Response('{"ok":false}', 200),
      ]) {
        expect(
          await Relay.detect(MockClient((_) async => response), page),
          isNull,
        );
      }
      expect(
        await Relay.detect(
          MockClient((_) async => throw http.ClientException('offline')),
          page,
        ),
        isNull,
      );
    });
  });

  test('instanceBase appends the upstream path under the relay', () {
    expect(
      Relay.instanceBase(Uri.parse('https://example.com'), 'id-1'),
      Uri.parse('https://example.com/hermes/id-1'),
    );
  });
}
