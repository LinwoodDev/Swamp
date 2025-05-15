import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';

part 'config.mapper.dart';

@MappableClass()
final class SwampConfig with SwampConfigMappable {
  static const descriptionEnvironment = 'SWAMP_DESCRIPTION';
  final String description;
  static const maxPlayersEnvironment = 'SWAMP_MAX_PLAYERS';
  final int maxPlayers;
  static const noDarkRoomsEnvironment = 'SWAMP_NO_DARK_ROOMS';
  final bool noDarkRooms;

  const SwampConfig({
    this.description = "",
    this.maxPlayers = 256,
    this.noDarkRooms = false,
  });

  factory SwampConfig.withEnvironment(
    Map<String, dynamic> data, {
    String? description,
    int? maxPlayers,
    bool? noDarkRooms,
  }) {
    final descriptionEnv = String.fromEnvironment(descriptionEnvironment);
    final maxPlayersEnv = int.fromEnvironment(
      maxPlayersEnvironment,
      defaultValue: -1,
    );
    final noDarkRoomsEnv = bool.fromEnvironment(noDarkRoomsEnvironment);
    return SwampConfigMapper.fromMap({
      ...data,
      if (descriptionEnv.isNotEmpty) 'description': descriptionEnv,
      if (maxPlayersEnv >= 0) 'maxPlayers': maxPlayersEnv,
      if (bool.hasEnvironment(noDarkRoomsEnvironment))
        'noDarkRooms': noDarkRoomsEnv,
      if (noDarkRooms != null) 'noDarkRooms': noDarkRooms,
      if (maxPlayers != null) 'maxPlayers': maxPlayers,
      if (description != null) 'description': description,
    });
  }

  int get flags => noDarkRooms ? 0x01 : 0x00;
}

final class ConfigManager {
  SwampConfig _config;

  SwampConfig get config => _config;

  ConfigManager([this._config = const SwampConfig()]);

  Future<void> load() async {
    final file = File('swamp.json');
    final data = await file.readAsString();
    _config = SwampConfigMapper.fromJson(data);
  }
}
