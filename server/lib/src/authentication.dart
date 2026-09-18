import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:networker/networker.dart';

/// The credentials and connection metadata passed to an
/// [AuthenticationSource].
final class AuthenticationRequest {
  /// A bearer token supplied by the client, if any.
  final String? token;

  /// The URI used for the WebSocket handshake.
  final Uri uri;

  /// The remote address of the connecting client, if available.
  final InternetAddress? remoteAddress;

  const AuthenticationRequest({
    required this.uri,
    this.token,
    this.remoteAddress,
  });

  factory AuthenticationRequest.fromHttpRequest(HttpRequest request) {
    return AuthenticationRequest(
      uri: request.uri,
      remoteAddress: request.connectionInfo?.remoteAddress,
    );
  }
}

/// An authenticated Swamp user and the permissions granted by its source.
final class AuthenticatedUser {
  /// Stable identifier used for connection limits.
  final String id;

  /// Whether this user may create rooms.
  final bool canCreateRooms;

  const AuthenticatedUser({required this.id, this.canCreateRooms = true});
}

/// A provider capable of resolving connection credentials to a user.
abstract class AuthenticationSource {
  Future<AuthenticatedUser?> authenticate(AuthenticationRequest request);

  Future<void> close() async {}
}

/// Authentication source backed by an in-memory token map.
final class StaticAuthenticationSource extends AuthenticationSource {
  final Map<String, AuthenticatedUser> _usersByToken;

  StaticAuthenticationSource(Map<String, AuthenticatedUser> usersByToken)
    : _usersByToken = Map.unmodifiable(usersByToken);

  @override
  Future<AuthenticatedUser?> authenticate(AuthenticationRequest request) async {
    final token = request.token;
    return token == null ? null : _usersByToken[token];
  }
}

/// Authentication source backed by a JSON file.
///
/// The file may either be a token map directly or contain it under `tokens`:
/// ```json
/// {
///   "tokens": {
///     "secret": {"userId": "alice", "canCreateRooms": true},
///     "another-secret": "bob"
///   }
/// }
/// ```
/// The file is reloaded when its modification time changes.
final class StaticFileAuthenticationSource extends AuthenticationSource {
  final File file;
  DateTime? _lastModified;
  Map<String, AuthenticatedUser> _usersByToken = const {};

  StaticFileAuthenticationSource(String path) : file = File(path);

  Future<void> _reloadIfNeeded() async {
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw AuthenticationSourceException('Authentication file not found');
    }
    if (_lastModified == stat.modified) return;

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw AuthenticationSourceException(
        'Authentication file must contain a JSON object',
      );
    }
    final rawTokens = decoded['tokens'] ?? decoded;
    if (rawTokens is! Map) {
      throw AuthenticationSourceException(
        'Authentication file tokens must be a JSON object',
      );
    }

    final users = <String, AuthenticatedUser>{};
    for (final entry in rawTokens.entries) {
      final token = entry.key;
      final value = entry.value;
      if (token is! String || token.isEmpty) continue;
      if (value is String && value.isNotEmpty) {
        users[token] = AuthenticatedUser(id: value);
      } else if (value is Map) {
        final id = value['userId'] ?? value['id'];
        if (id is String && id.isNotEmpty) {
          users[token] = AuthenticatedUser(
            id: id,
            canCreateRooms: _readPermission(value),
          );
        }
      }
    }
    _usersByToken = Map.unmodifiable(users);
    _lastModified = stat.modified;
  }

  @override
  Future<AuthenticatedUser?> authenticate(AuthenticationRequest request) async {
    await _reloadIfNeeded();
    final token = request.token;
    return token == null ? null : _usersByToken[token];
  }

  static bool _readPermission(Map<dynamic, dynamic> value) {
    final permission = value['canCreateRooms'] ?? value['canCreate'];
    if (permission == null) return true;
    if (permission is bool) return permission;
    throw AuthenticationSourceException(
      'canCreateRooms must be a JSON boolean',
    );
  }
}

/// Authentication source that validates credentials using a REST endpoint.
///
/// It sends a JSON POST body containing `token`, `requestUri`, and
/// `remoteAddress`. A successful response must contain `userId` (or `id`) and
/// may contain `canCreateRooms` (or `canCreate`). A 401 or 403 response means
/// that the credentials are invalid; other non-success responses are treated
/// as source failures.
final class RestApiAuthenticationSource extends AuthenticationSource {
  final Uri endpoint;
  final Duration timeout;
  final HttpClient _client;
  final bool _ownsClient;

  RestApiAuthenticationSource(
    this.endpoint, {
    this.timeout = const Duration(seconds: 10),
    HttpClient? client,
  }) : _client = client ?? HttpClient(),
       _ownsClient = client == null;

  @override
  Future<AuthenticatedUser?> authenticate(AuthenticationRequest request) async {
    final token = request.token;
    if (token == null || token.isEmpty) return null;

    final outgoing = await _client.postUrl(endpoint).timeout(timeout);
    outgoing.headers.contentType = ContentType.json;
    outgoing.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    outgoing.write(
      jsonEncode({
        'token': token,
        'requestUri': request.uri.toString(),
        'remoteAddress': request.remoteAddress?.address,
      }),
    );
    final response = await outgoing.close().timeout(timeout);
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      await response.drain();
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain();
      throw AuthenticationSourceException(
        'Authentication endpoint returned HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(await response.transform(utf8.decoder).join());
    if (decoded is! Map) {
      throw AuthenticationSourceException(
        'Authentication endpoint returned an invalid response',
      );
    }
    final id = decoded['userId'] ?? decoded['id'];
    if (id is! String || id.isEmpty) return null;
    return AuthenticatedUser(id: id, canCreateRooms: _readPermission(decoded));
  }

  static bool _readPermission(Map<dynamic, dynamic> value) {
    final permission = value['canCreateRooms'] ?? value['canCreate'];
    if (permission == null) return true;
    if (permission is bool) return permission;
    throw AuthenticationSourceException(
      'Authentication endpoint canCreateRooms must be a JSON boolean',
    );
  }

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close(force: true);
  }
}

/// Controls which operations require authentication.
final class AuthenticationPolicy {
  /// Require protocol-level authentication before using the connection.
  final bool requireForConnection;

  /// Reject room creation by unauthenticated users.
  final bool requireForRoomCreation;

  /// Maximum simultaneous connections per authenticated user.
  /// `null` means unlimited.
  final int? maxConnectionsPerUser;

  /// Time allowed for protocol-level authentication after connecting.
  final Duration authenticationTimeout;

  const AuthenticationPolicy({
    this.requireForConnection = true,
    this.requireForRoomCreation = true,
    this.maxConnectionsPerUser,
    this.authenticationTimeout = const Duration(seconds: 10),
  }) : assert(
         maxConnectionsPerUser == null || maxConnectionsPerUser > 0,
         'maxConnectionsPerUser must be greater than zero',
       );
}

/// Combines authentication sources with connection and creation policy.
final class SwampAuthentication {
  final List<AuthenticationSource> sources;
  final AuthenticationPolicy policy;

  const SwampAuthentication({
    required this.sources,
    this.policy = const AuthenticationPolicy(),
  });

  Future<AuthenticatedUser?> authenticate(AuthenticationRequest request) async {
    for (final source in sources) {
      final user = await source.authenticate(request);
      if (user != null) return user;
    }
    return null;
  }

  Future<void> close() async {
    for (final source in sources) {
      await source.close();
    }
  }
}

/// Creates authentication configuration from Swamp environment variables.
///
/// `SWAMP_AUTH_FILE` and `SWAMP_AUTH_URL` accept comma-separated values. Static
/// files are tried first in their listed order, followed by REST endpoints in
/// their listed order.
SwampAuthentication? swampAuthenticationFromEnvironment(
  Map<String, String> environment,
) {
  final sources = <AuthenticationSource>[
    for (final path in _environmentList(environment, 'SWAMP_AUTH_FILE'))
      StaticFileAuthenticationSource(path),
    for (final endpoint in _environmentList(environment, 'SWAMP_AUTH_URL'))
      RestApiAuthenticationSource(Uri.parse(endpoint)),
  ];
  if (sources.isEmpty) return null;

  final maximumText = environment['SWAMP_AUTH_MAX_CONNECTIONS_PER_USER'];
  final maximum = maximumText == null ? null : int.tryParse(maximumText);
  if (maximumText != null && (maximum == null || maximum <= 0)) {
    throw FormatException(
      'SWAMP_AUTH_MAX_CONNECTIONS_PER_USER must be a positive integer',
    );
  }

  return SwampAuthentication(
    sources: sources,
    policy: AuthenticationPolicy(
      requireForConnection: _environmentBool(
        environment,
        'SWAMP_AUTH_REQUIRE_CONNECTION',
        defaultValue: true,
      ),
      requireForRoomCreation: _environmentBool(
        environment,
        'SWAMP_AUTH_REQUIRE_CREATE',
        defaultValue: true,
      ),
      maxConnectionsPerUser: maximum,
    ),
  );
}

Iterable<String> _environmentList(
  Map<String, String> environment,
  String name,
) sync* {
  final value = environment[name];
  if (value == null) return;
  for (final item in value.split(',')) {
    final trimmed = item.trim();
    if (trimmed.isNotEmpty) yield trimmed;
  }
}

bool _environmentBool(
  Map<String, String> environment,
  String name, {
  required bool defaultValue,
}) {
  final value = environment[name]?.toLowerCase();
  if (value == null || value.isEmpty) return defaultValue;
  return value == 'true' || value == '1' || value == 'yes';
}

/// The outcome of a protocol-level authentication attempt.
enum AuthenticationAttemptResult {
  /// The channel is authenticated.
  authenticated,

  /// The supplied credentials or the connection limit rejected the channel.
  rejected,

  /// An authentication attempt is already running for the channel.
  inProgress,
}

/// Owns authentication state for active server connections.
///
/// This keeps connection lifecycle, authenticated identities, timeouts, and
/// per-user connection limits separate from the main server implementation.
final class SwampAuthenticationManager {
  /// The authentication sources and policy managed by this instance.
  final SwampAuthentication authentication;

  final Map<Channel, AuthenticatedUser> _authenticatedUsers = {};
  final Map<String, int> _connectionsPerUser = {};
  final Map<Channel, AuthenticationRequest> _authenticationRequests = {};
  final Map<Channel, Timer> _authenticationTimeouts = {};
  final Set<Channel> _authenticating = {};

  /// Creates a manager for [authentication].
  SwampAuthenticationManager(this.authentication);

  /// Whether connections must authenticate before sending normal commands.
  bool get requiresAuthentication => authentication.policy.requireForConnection;

  /// Registers the authentication context for a newly connected channel.
  void connected(
    Channel channel,
    AuthenticationRequest request, {
    required void Function() onTimeout,
  }) {
    _authenticationRequests[channel] = request;
    if (requiresAuthentication) {
      _authenticationTimeouts[channel] = Timer(
        authentication.policy.authenticationTimeout,
        onTimeout,
      );
    }
  }

  /// Releases all authentication state associated with [channel].
  void disconnected(Channel channel) {
    _authenticationTimeouts.remove(channel)?.cancel();
    _authenticating.remove(channel);
    _authenticationRequests.remove(channel);
    final user = _authenticatedUsers.remove(channel);
    if (user != null) _releaseConnection(user);
  }

  /// Whether [channel] may use commands that require an active connection.
  bool isConnectionAuthorized(Channel channel) {
    return !requiresAuthentication || _authenticatedUsers.containsKey(channel);
  }

  /// Whether [channel] may create a room under the configured policy.
  bool canCreateRooms(Channel channel) {
    final user = _authenticatedUsers[channel];
    if (authentication.policy.requireForRoomCreation && user == null) {
      return false;
    }
    return user?.canCreateRooms ?? true;
  }

  /// Authenticates [channel] with [token] and reserves its user connection.
  Future<AuthenticationAttemptResult> authenticate(
    Channel channel,
    String token,
  ) async {
    if (_authenticatedUsers.containsKey(channel)) {
      return AuthenticationAttemptResult.authenticated;
    }
    if (!_authenticating.add(channel)) {
      return AuthenticationAttemptResult.inProgress;
    }

    try {
      final request = _authenticationRequests[channel];
      if (request == null) return AuthenticationAttemptResult.rejected;

      final user = await authentication.authenticate(
        AuthenticationRequest(
          uri: request.uri,
          token: token,
          remoteAddress: request.remoteAddress,
        ),
      );
      if (user == null ||
          !identical(_authenticationRequests[channel], request) ||
          !_reserveConnection(user)) {
        return AuthenticationAttemptResult.rejected;
      }

      _authenticatedUsers[channel] = user;
      _authenticationTimeouts.remove(channel)?.cancel();
      return AuthenticationAttemptResult.authenticated;
    } finally {
      _authenticating.remove(channel);
    }
  }

  bool _reserveConnection(AuthenticatedUser user) {
    final maximum = authentication.policy.maxConnectionsPerUser;
    final current = _connectionsPerUser[user.id] ?? 0;
    if (maximum != null && current >= maximum) return false;
    _connectionsPerUser[user.id] = current + 1;
    return true;
  }

  void _releaseConnection(AuthenticatedUser user) {
    final current = _connectionsPerUser[user.id] ?? 0;
    if (current <= 1) {
      _connectionsPerUser.remove(user.id);
    } else {
      _connectionsPerUser[user.id] = current - 1;
    }
  }

  /// Cancels pending timeouts, clears runtime state, and closes all sources.
  Future<void> close() async {
    for (final timeout in _authenticationTimeouts.values) {
      timeout.cancel();
    }
    _authenticationTimeouts.clear();
    _authenticationRequests.clear();
    _authenticating.clear();
    _authenticatedUsers.clear();
    _connectionsPerUser.clear();
    await authentication.close();
  }
}

final class AuthenticationSourceException implements Exception {
  final String message;

  const AuthenticationSourceException(this.message);

  @override
  String toString() => 'AuthenticationSourceException: $message';
}
