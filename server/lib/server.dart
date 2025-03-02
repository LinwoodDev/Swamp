import 'dart:async';
import 'dart:io';

import 'package:networker/networker.dart';
import 'package:networker_socket/server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:swamp/config.dart';
import 'package:swamp/room.dart';
import 'package:swamp_api/models.dart';

// Configure routes.
final _router =
    Router()
      ..get('/', _rootHandler)
      ..get('/echo/<message>', _echoHandler);

Response _rootHandler(Request req) {
  return Response.ok('Hello, World!\n');
}

Response _echoHandler(Request request) {
  final message = request.params['message'];
  return Response.ok('$message\n');
}

Future<void> startServer({
  SwampConfig config = const SwampConfig(),
  int port = 8080,
  InternetAddress? address,
}) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Configure a pipeline that logs requests.
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}

final class SwampRoom {
  final int roomFlags;

  SwampRoom({required this.roomFlags});
}

class SwampServer extends NetworkerSocketServer {
  final SwampRoomManager _roomManager = SwampRoomManager();
  final NamedRpcClientNetworkerPipe<SwampCommand, SwampEvent> _rpcPipe =
      NamedRpcClientNetworkerPipe();

  SwampServer(super.serverAddress, super.port) {
    connect(_rpcPipe..connect(_roomManager));

    _initFunctions();
  }

  void _initFunctions() {
    _rpcPipe.registerNamedFunction(SwampCommand.createRoom).read.listen((
      event,
    ) {
      _roomManager.addRoom(event.channel);
    });
  }
}
