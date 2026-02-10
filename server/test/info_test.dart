import 'dart:convert';
import 'dart:io';

import 'package:consoler/consoler.dart';
import 'package:swamp/src/server.dart';
import 'package:swamp_api/models.dart';
import 'package:test/test.dart';

void main() {
  final port = 8081;
  final host = '127.0.0.1';
  late SwampServer server;

  setUp(() async {
    server = SwampServer(
      host,
      port,
      minLogLevel: LogLevel.verbose,
      withConsole: false,
    );
    await server.init();
  });

  tearDown(() async {
    await server.close();
  });

  group('Server Info Tests', () {
    test('Get server info via HTTP', () async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://$host:$port/info'),
        );
        final response = await request.close();

        expect(response.statusCode, HttpStatus.ok);
        expect(
          response.headers.contentType?.mimeType,
          ContentType.json.mimeType,
        );

        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(data['name'], isNotEmpty);
        expect(data['rooms'], isNotNull);
        expect(data['players'], isNotNull);
        expect(data['protocols'], isList);
        expect(data['protocols'], contains(1));
      } finally {
        client.close();
      }
    });

    test('Info endpoint rejects non-GET requests', () async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://$host:$port/info'),
        );
        final response = await request.close();
        await response.drain();

        expect(response.statusCode, HttpStatus.methodNotAllowed);
      } finally {
        client.close();
      }
    });

    test(
      'Info endpoint returns JSON (not upgrade) for WebSocket upgrade request',
      () async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            Uri.parse('http://$host:$port/info'),
          );
          request.headers.set('Connection', 'Upgrade');
          request.headers.set('Upgrade', 'websocket');
          request.headers.set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
          request.headers.set('Sec-WebSocket-Version', '13');

          final response = await request.close();
          expect(response.statusCode, HttpStatus.ok);
          expect(
            response.headers.contentType?.mimeType,
            ContentType.json.mimeType,
          );
          await response.drain();
        } finally {
          client.close();
        }
      },
    );
  });

  group('Protocol Negotiation Tests', () {
    test('WebSocket upgrade succeeds with supported protocol', () async {
      final ws = await WebSocket.connect(
        'ws://$host:$port',
        protocols: [swampSubprotocol(kSwampProtocolVersion)],
      );
      expect(ws.protocol, swampSubprotocol(kSwampProtocolVersion));
      await ws.close();
    });

    test('WebSocket upgrade rejected for unsupported protocol', () async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('http://$host:$port'));
        request.headers.set('Connection', 'Upgrade');
        request.headers.set('Upgrade', 'websocket');
        request.headers.set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
        request.headers.set('Sec-WebSocket-Version', '13');
        request.headers.set('Sec-WebSocket-Protocol', 'swamp-999');

        final response = await request.close();
        expect(response.statusCode, HttpStatus.badRequest);

        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        expect(data['error'], 'unsupported_protocol');
        expect(data['supported'], isList);
        expect(data['supported'], isNotEmpty);
      } finally {
        client.close();
      }
    });

    test('Info endpoint advertises protocol versions', () async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://$host:$port/info'),
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        expect(data['protocols'], isList);
        expect(data['protocols'], contains(kSwampProtocolVersion));
      } finally {
        client.close();
      }
    });
  });
}
