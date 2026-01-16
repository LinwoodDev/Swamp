import 'dart:convert';
import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';

part 'config.mapper.dart';

@MappableClass()
final class SwampConfig with SwampConfigMappable {
  /// Environment variable for the server description.
  static const descriptionEnvironment = 'SWAMP_DESCRIPTION';

  /// A description of the server.
  final String description;

  /// Environment variable for the maximum number of players.
  static const maxPlayersEnvironment = 'SWAMP_MAX_PLAYERS';

  /// The maximum number of players allowed on the server.
  final int maxPlayers;

  /// Environment variable to disable dark rooms.
  static const noDarkRoomsEnvironment = 'SWAMP_NO_DARK_ROOMS';

  /// Whether dark rooms are disabled on this server.
  final bool noDarkRooms;

  const SwampConfig({
    this.description = "",
    this.maxPlayers = 256,
    this.noDarkRooms = false,
  });

  /// Creates a [SwampConfig] merging default values, environment variables, and provided parameters.
  ///
  /// Environment variables take precedence over defaults, and explicit parameters take precedence over environment variables.
  factory SwampConfig.withEnvironment(
    Map<String, dynamic> data, {
    String? description,
    int? maxPlayers,
    bool? noDarkRooms,
  }) {
    final descriptionEnv =
        Platform.environment[descriptionEnvironment] ??
        String.fromEnvironment(descriptionEnvironment);
    final maxPlayersEnvString =
        Platform.environment[maxPlayersEnvironment] ??
        (int.fromEnvironment(maxPlayersEnvironment, defaultValue: -1) == -1
            ? null
            : int.fromEnvironment(maxPlayersEnvironment).toString());
    final maxPlayersEnv = maxPlayersEnvString != null
        ? int.tryParse(maxPlayersEnvString)
        : null;

    final noDarkRoomsEnvString =
        Platform.environment[noDarkRoomsEnvironment] ??
        (bool.fromEnvironment(noDarkRoomsEnvironment) ? 'true' : null);
    final noDarkRoomsEnv =
        noDarkRoomsEnvString?.toLowerCase() == 'true' ||
        noDarkRoomsEnvString == '1';

    return SwampConfigMapper.fromMap({
      ...data,
      if (descriptionEnv.isNotEmpty) 'description': descriptionEnv,
      if (maxPlayersEnv != null && maxPlayersEnv >= 0)
        'maxPlayers': maxPlayersEnv,
      if (noDarkRoomsEnv) 'noDarkRooms': true,
      if (noDarkRooms != null) 'noDarkRooms': noDarkRooms,
      if (maxPlayers != null) 'maxPlayers': maxPlayers,
      if (description != null) 'description': description,
    });
  }

  int get flags => noDarkRooms ? 0x01 : 0x00;
}

/// Manages the runtime configuration of the server.
final class ConfigManager {
  SwampConfig _config;

  SwampConfig get config => _config;

  ConfigManager([SwampConfig? config])
    : _config = config ?? SwampConfig.withEnvironment({});

  Future<void> load() async {
    final file = File('swamp.json');
    if (!await file.exists()) {
      _config = SwampConfig.withEnvironment({});
      return;
    }
    try {
      final json = await file.readAsString();
      final data = jsonDecode(json);
      if (data is Map<String, dynamic>) {
        _config = SwampConfig.withEnvironment(data);
      }
    } catch (e) {
      print('Failed to load swamp.json: $e');
    }
  }
}
