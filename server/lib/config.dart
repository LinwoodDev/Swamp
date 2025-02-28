final class SwampConfig {
  final String description;
  final int maxPlayers;
  final bool noDarkRooms;

  const SwampConfig({
    this.description = "",
    this.maxPlayers = 256,
    this.noDarkRooms = false,
  });

  int get flags => noDarkRooms ? 0x01 : 0x00;
}
