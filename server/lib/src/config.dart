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

  /// Environment variable for the maximum players allowed in one room.
  static const maxPlayersPerRoomEnvironment = 'SWAMP_MAX_PLAYERS_PER_ROOM';

  /// The maximum number of players allowed in a room.
  final int maxPlayersPerRoom;

  /// Environment variable for the maximum concurrent players on the server.
  static const maxConcurrentPlayersEnvironment = 'SWAMP_MAX_CONCURRENT_PLAYERS';

  /// The maximum number of players across all rooms. Zero means unlimited.
  final int maxConcurrentPlayers;

  /// Environment variable for the maximum number of rooms.
  static const maxRoomsEnvironment = 'SWAMP_MAX_ROOMS';

  /// The maximum number of active rooms. Zero means unlimited.
  final int maxRooms;

  /// Environment variable to disable dark rooms.
  static const noDarkRoomsEnvironment = 'SWAMP_NO_DARK_ROOMS';

  /// Whether dark rooms are disabled on this server.
  final bool noDarkRooms;

  const SwampConfig({
    this.description = "",
    this.maxPlayersPerRoom = 1024,
    this.maxConcurrentPlayers = 0,
    this.maxRooms = 0,
    this.noDarkRooms = false,
  });

  /// Creates a [SwampConfig] merging default values, environment variables, and provided parameters.
  ///
  /// Environment variables take precedence over defaults, and explicit parameters take precedence over environment variables.
  factory SwampConfig.withEnvironment(
    Map<String, dynamic> data, {
    String? description,
    int? maxPlayersPerRoom,
    int? maxConcurrentPlayers,
    int? maxRooms,
    bool? noDarkRooms,
  }) {
    final descriptionEnv =
        Platform.environment[descriptionEnvironment] ??
        String.fromEnvironment(descriptionEnvironment);
    final maxPlayersPerRoomEnvString =
        Platform.environment[maxPlayersPerRoomEnvironment] ??
        (int.fromEnvironment(maxPlayersPerRoomEnvironment, defaultValue: -1) ==
                -1
            ? null
            : int.fromEnvironment(maxPlayersPerRoomEnvironment).toString());
    final maxPlayersPerRoomEnv = maxPlayersPerRoomEnvString != null
        ? int.tryParse(maxPlayersPerRoomEnvString)
        : null;
    final maxConcurrentPlayersEnvString =
        Platform.environment[maxConcurrentPlayersEnvironment] ??
        (int.fromEnvironment(
                  maxConcurrentPlayersEnvironment,
                  defaultValue: -1,
                ) ==
                -1
            ? null
            : int.fromEnvironment(maxConcurrentPlayersEnvironment).toString());
    final maxConcurrentPlayersEnv = maxConcurrentPlayersEnvString != null
        ? int.tryParse(maxConcurrentPlayersEnvString)
        : null;
    final maxRoomsEnvString =
        Platform.environment[maxRoomsEnvironment] ??
        (int.fromEnvironment(maxRoomsEnvironment, defaultValue: -1) == -1
            ? null
            : int.fromEnvironment(maxRoomsEnvironment).toString());
    final maxRoomsEnv = maxRoomsEnvString != null
        ? int.tryParse(maxRoomsEnvString)
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
      if (maxPlayersPerRoomEnv != null && maxPlayersPerRoomEnv >= 0)
        'maxPlayersPerRoom': maxPlayersPerRoomEnv,
      if (maxConcurrentPlayersEnv != null && maxConcurrentPlayersEnv >= 0)
        'maxConcurrentPlayers': maxConcurrentPlayersEnv,
      if (maxRoomsEnv != null && maxRoomsEnv >= 0) 'maxRooms': maxRoomsEnv,
      if (noDarkRoomsEnv) 'noDarkRooms': true,
      'noDarkRooms': ?noDarkRooms,
      'maxPlayersPerRoom': ?maxPlayersPerRoom,
      'maxConcurrentPlayers': ?maxConcurrentPlayers,
      'maxRooms': ?maxRooms,
      'description': ?description,
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
