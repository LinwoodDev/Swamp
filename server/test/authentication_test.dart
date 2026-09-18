import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:consoler/consoler.dart';
import 'package:swamp/swamp.dart';
import 'package:swamp_api/connection.dart';
import 'package:test/test.dart';

void main() {
  const host = '127.0.0.1';
  const port = 8082;
  final uri = Uri.parse('ws://$host:$port');

  group('authentication sources', () {
    test('environment accepts multiple files and REST endpoints', () async {
      final authentication = swampAuthenticationFromEnvironment({
        'SWAMP_AUTH_FILE': 'first.json, second.json, ',
        'SWAMP_AUTH_URL': 'https://auth.example/one, https://auth.example/two',
      });

      expect(authentication, isNotNull);
      final sources = authentication!.sources;
      expect(sources, hasLength(4));
      expect(
        (sources[0] as StaticFileAuthenticationSource).file.path,
        'first.json',
      );
      expect(
        (sources[1] as StaticFileAuthenticationSource).file.path,
        'second.json',
      );
      expect(
        (sources[2] as RestApiAuthenticationSource).endpoint,
        Uri.parse('https://auth.example/one'),
      );
      expect(
        (sources[3] as RestApiAuthenticationSource).endpoint,
        Uri.parse('https://auth.example/two'),
      );
      await authentication.close();
    });

    test('static file resolves users and creation permissions', () async {
      final directory = await Directory.systemTemp.createTemp('swamp-auth-');
      final file = File('${directory.path}/users.json');
      await file.writeAsString(
        jsonEncode({
          'tokens': {
            'creator-token': {'userId': 'creator', 'canCreateRooms': true},
            'guest-token': {'userId': 'guest', 'canCreateRooms': false},
          },
        }),
      );
      final source = StaticFileAuthenticationSource(file.path);

      try {
        final creator = await source.authenticate(
          AuthenticationRequest(uri: uri, token: 'creator-token'),
        );
        final guest = await source.authenticate(
          AuthenticationRequest(uri: uri, token: 'guest-token'),
        );

        expect(creator?.id, 'creator');
        expect(creator?.canCreateRooms, isTrue);
        expect(guest?.id, 'guest');
        expect(guest?.canCreateRooms, isFalse);
        expect(
          await source.authenticate(
            AuthenticationRequest(uri: uri, token: 'invalid'),
          ),
          isNull,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('REST source resolves the endpoint response', () async {
      final endpoint = await HttpServer.bind(host, 0);
      final requestHandled = Completer<void>();
      endpoint.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer rest-token',
        );
        expect(body['token'], 'rest-token');
        expect(body['requestUri'], uri.toString());
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'userId': 'rest-user', 'canCreateRooms': false}),
        );
        await request.response.close();
        requestHandled.complete();
      });
      final source = RestApiAuthenticationSource(
        Uri.parse('http://$host:${endpoint.port}/authenticate'),
      );

      try {
        final user = await source.authenticate(
          AuthenticationRequest(uri: uri, token: 'rest-token'),
        );
        await requestHandled.future;
        expect(user?.id, 'rest-user');
        expect(user?.canCreateRooms, isFalse);
      } finally {
        await source.close();
        await endpoint.close(force: true);
      }
    });
  });

  group('server authentication', () {
    late SwampServer server;
    final clients = <RawSwampConnection>[];

    tearDown(() async {
      for (final client in clients) {
        await client.close();
      }
      clients.clear();
      await server.close();
    });

    test('closes connections that do not authenticate', () async {
      server = _authenticatedServer(host, port);
      await server.init();
      final client = RawSwampConnection(server: uri);
      clients.add(client);
      final closed = client.onClosed.first;

      await client.init();
      await closed.timeout(const Duration(seconds: 2));
    });

    test('blocks commands until authentication succeeds', () async {
      server = SwampServer(
        host,
        port,
        withConsole: false,
        minLogLevel: LogLevel.error,
        authentication: SwampAuthentication(
          sources: [StaticAuthenticationSource(const {})],
          policy: const AuthenticationPolicy(
            authenticationTimeout: Duration(seconds: 5),
          ),
        ),
      );
      await server.init();
      final client = RawSwampConnection(server: uri);
      clients.add(client);
      await client.init();
      final closed = client.onClosed.first;

      client.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      await closed.timeout(const Duration(seconds: 2));
      expect(server.roomManager.playerCount, 0);
    });

    test('limits simultaneous connections per user', () async {
      server = _authenticatedServer(host, port);
      await server.init();
      final first = RawSwampConnection(server: uri, accessToken: 'creator');
      final second = RawSwampConnection(server: uri, accessToken: 'creator');
      clients.addAll([first, second]);

      await first.init();
      await expectLater(second.init(), throwsA(anything));
      await first.close();
      clients.remove(first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await second.init();
    });

    test('denies room creation without the source permission', () async {
      server = _authenticatedServer(host, port);
      await server.init();
      final client = RawSwampConnection(server: uri, accessToken: 'guest');
      clients.add(client);
      await client.init();
      final failed = client
          .registerNamedFunction(SwampEvent.roomCreationFailed)
          .read
          .first;

      client.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      final packet = await failed.timeout(const Duration(seconds: 2));
      expect(
        CreationFailedReason.fromValue(packet.data.single),
        CreationFailedReason.unauthorized,
      );
    });

    test(
      'can allow anonymous connections but restrict room creation',
      () async {
        server = SwampServer(
          host,
          port,
          withConsole: false,
          minLogLevel: LogLevel.error,
          authentication: SwampAuthentication(
            sources: [StaticAuthenticationSource(const {})],
            policy: const AuthenticationPolicy(requireForConnection: false),
          ),
        );
        await server.init();
        final client = RawSwampConnection(server: uri);
        clients.add(client);
        await client.init();
        final failed = client
            .registerNamedFunction(SwampEvent.roomCreationFailed)
            .read
            .first;

        client.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

        final packet = await failed.timeout(const Duration(seconds: 2));
        expect(
          CreationFailedReason.fromValue(packet.data.single),
          CreationFailedReason.unauthorized,
        );
      },
    );
  });
}

SwampServer _authenticatedServer(String host, int port) {
  return SwampServer(
    host,
    port,
    withConsole: false,
    minLogLevel: LogLevel.error,
    authentication: SwampAuthentication(
      sources: [
        StaticAuthenticationSource({
          'creator': const AuthenticatedUser(id: 'user-1'),
          'guest': const AuthenticatedUser(id: 'user-2', canCreateRooms: false),
        }),
      ],
      policy: const AuthenticationPolicy(
        maxConnectionsPerUser: 1,
        authenticationTimeout: Duration(milliseconds: 200),
      ),
    ),
  );
}
