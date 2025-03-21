import 'dart:typed_data';

import 'package:swamp_api/models.dart';
import 'package:test/test.dart';

void main() {
  group('Room Encoder', () {
    test("Encode and decode room code", () {
      final code = decodeRoomCode("4312");
      expect(encodeRoomCode(code), "4312");
    });
    test("Encode and decode the same length", () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final encoded = encodeRoomCode(bytes);
      final decoded = decodeRoomCode(encoded);
      expect(decoded.length, bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        expect(decoded[i], bytes[i]);
      }
    });
  });
}
