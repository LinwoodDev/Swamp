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

  /// Merges defaults, file values, environment values, then explicit overrides.
  /// Invalid values are rejected rather than silently falling back to defaults.
  factory SwampConfig.withEnvironment(
    Map<String, dynamic> data, {
    Map<String, String>? environment,
    String? description,
    int? maxPlayersPerRoom,
    int? maxConcurrentPlayers,
    int? maxRooms,
    bool? noDarkRooms,
  }) {
    final env = environment ?? Platform.environment;
    const compileTime = {
      if (bool.hasEnvironment(descriptionEnvironment))
        descriptionEnvironment: String.fromEnvironment(descriptionEnvironment),
      if (bool.hasEnvironment(maxPlayersPerRoomEnvironment))
        maxPlayersPerRoomEnvironment: String.fromEnvironment(
          maxPlayersPerRoomEnvironment,
        ),
      if (bool.hasEnvironment(maxConcurrentPlayersEnvironment))
        maxConcurrentPlayersEnvironment: String.fromEnvironment(
          maxConcurrentPlayersEnvironment,
        ),
      if (bool.hasEnvironment(maxRoomsEnvironment))
        maxRoomsEnvironment: String.fromEnvironment(maxRoomsEnvironment),
      if (bool.hasEnvironment(noDarkRoomsEnvironment))
        noDarkRoomsEnvironment: String.fromEnvironment(noDarkRoomsEnvironment),
    };
    String? value(String name) => env[name] ?? compileTime[name];
    int? integer(String name, int? override) {
      if (override != null) return override;
      final raw = value(name);
      if (raw == null) return null;
      final parsed = int.tryParse(raw.trim());
      if (parsed == null) throw FormatException('$name must be an integer.');
      return parsed;
    }

    bool? boolean(String name, bool? override) {
      if (override != null) return override;
      final raw = value(name)?.trim().toLowerCase();
      return switch (raw) {
        null => null,
        'true' || '1' => true,
        'false' || '0' => false,
        _ => throw FormatException('$name must be true, false, 1, or 0.'),
      };
    }

    final config = SwampConfigMapper.fromMap({
      ...data,
      'description': ?(description ?? value(descriptionEnvironment)),
      'maxPlayersPerRoom': ?integer(
        maxPlayersPerRoomEnvironment,
        maxPlayersPerRoom,
      ),
      'maxConcurrentPlayers': ?integer(
        maxConcurrentPlayersEnvironment,
        maxConcurrentPlayers,
      ),
      'maxRooms': ?integer(maxRoomsEnvironment, maxRooms),
      'noDarkRooms': ?boolean(noDarkRoomsEnvironment, noDarkRooms),
    });
    config.validate();
    return config;
  }

  /// Checks limits against the room protocol and unlimited-value conventions.
  void validate() {
    if (maxPlayersPerRoom < 1 || maxPlayersPerRoom > 65535) {
      throw const FormatException(
        'maxPlayersPerRoom must be between 1 and 65535.',
      );
    }
    if (maxConcurrentPlayers < 0) {
      throw const FormatException(
        'maxConcurrentPlayers must be zero or greater.',
      );
    }
    if (maxRooms < 0) {
      throw const FormatException('maxRooms must be zero or greater.');
    }
  }

  int get flags => noDarkRooms ? 0x01 : 0x00;
}

/// Manages the runtime configuration of the server.
final class ConfigManager {
  SwampConfig _config;

  SwampConfig get config => _config;

  /// Configuration file used by startup and console reloads.
  final String path;
  final Map<String, String>? environment;

  ConfigManager([SwampConfig? config]) : this.withOptions(config: config);

  ConfigManager.withOptions({
    SwampConfig? config,
    this.path = 'swamp.json',
    this.environment,
  }) : _config =
           config ?? SwampConfig.withEnvironment({}, environment: environment) {
    _config.validate();
  }

  /// Replaces the configuration only after a complete, successful load.
  /// A missing file uses defaults and environment values.
  Future<void> load() async {
    final file = File(path);
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('$path must contain a JSON object.');
      }
      data = decoded;
    }
    _config = SwampConfig.withEnvironment(data, environment: environment);
  }
}
