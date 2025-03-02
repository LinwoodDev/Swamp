part of 'connection.dart';

final class SwampClientConnectionInfo extends ConnectionInfo {
  final SwampConnection parent;
  final Channel channel;

  SwampClientConnectionInfo(this.parent, this.channel);

  @override
  Uri get address => parent.address;

  @override
  Future<void> close([String? message]) async {
    final socketChannel = parent._channel;
    if (socketChannel == null) return;
    socketChannel.sink.add([
      0x04,
      channel >> 8,
      channel & 0xFF,
      ...?message?.codeUnits,
    ]);
    return socketChannel.sink.close();
  }

  @override
  bool get isClosed => parent.clientConnections.contains(channel);

  @override
  void sendMessage(Uint8List data) {
    final socketChannel = parent._channel;
    if (socketChannel == null) return;
    socketChannel.sink.add([0x0, channel >> 8, channel & 0xFF, ...data]);
  }
}
