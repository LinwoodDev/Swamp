import 'dart:convert';
import 'dart:io';

import 'package:consoler/consoler.dart';
import 'package:swamp/src/server.dart';
import 'package:swamp_api/models.dart';

void showPublicInfo(SwampServer server, HttpRequest request) {
  try {
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.close();
      return;
    }
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.headers.add('Access-Control-Allow-Origin', '*');

    final data = {
      'name': server.config.description.isEmpty
          ? 'Swamp Server'
          : server.config.description,
      'rooms': server.roomManager.rooms.length,
      'players': server.roomManager.playerCount,
      'protocols': kSwampSupportedProtocols,
    };

    response.write(jsonEncode(data));
    response.close();
  } catch (e, stackTrace) {
    server.log('Failed to handle info request: $e', LogLevel.error);
    server.log(stackTrace, LogLevel.verbose);
    try {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.close();
    } catch (_) {
      // Ignore errors when closing the response if it failed
    }
  }
}
