import 'dart:async';

import 'package:networker/networker.dart';

class RateLimiterPipe<T> extends SimpleNetworkerPipe<T> {
  final int maxRequests;
  final Duration duration;
  final Map<Channel, List<DateTime>> _requests = {};
  Timer? _cleanupTimer;

  RateLimiterPipe({
    this.maxRequests = 100,
    this.duration = const Duration(minutes: 1),
    bool autoCleanup = true,
  }) {
    if (autoCleanup) {
      _cleanupTimer = Timer.periodic(duration, (_) => cleanup());
    }
  }

  bool _isAllowed(Channel key) {
    final now = DateTime.now();
    final timestamps = _requests.putIfAbsent(key, () => []);

    // Remove old timestamps lazily
    while (timestamps.isNotEmpty &&
        now.difference(timestamps.first) > duration) {
      timestamps.removeAt(0);
    }

    if (timestamps.length >= maxRequests) {
      return false;
    }

    timestamps.add(now);
    return true;
  }

  void cleanup() {
    final now = DateTime.now();
    _requests.removeWhere((key, timestamps) {
      while (timestamps.isNotEmpty &&
          now.difference(timestamps.first) > duration) {
        timestamps.removeAt(0);
      }
      return timestamps.isEmpty;
    });
  }

  @override
  void dispose() {
    super.dispose();
    _cleanupTimer?.cancel();
    _requests.clear();
  }

  @override
  FutureOr<(T, Channel)?> decodeChannel(T data, Channel channel) {
    if (!_isAllowed(channel)) {
      return null;
    }
    return super.decodeChannel(data, channel);
  }
}
