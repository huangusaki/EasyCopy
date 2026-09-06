import 'dart:async';

/// Drains current writers before a storage switch and queues new writers until
/// the switch finishes. Failed operations always release their reservation.
class DownloadStorageWriteBarrier {
  int _writers = 0;
  Completer<void>? _drained;
  Completer<void>? _switchDone;

  Future<T> write<T>(Future<T> Function() action) async {
    while (_switchDone != null) {
      await _switchDone!.future;
    }
    _writers += 1;
    try {
      return await action();
    } finally {
      _writers -= 1;
      if (_writers == 0) {
        _drained?.complete();
        _drained = null;
      }
    }
  }

  Future<T> switchStorage<T>(Future<T> Function() action) async {
    if (_switchDone != null) {
      throw StateError('A storage switch is already active.');
    }
    final Completer<void> done = Completer<void>();
    _switchDone = done;
    try {
      if (_writers > 0) {
        _drained = Completer<void>();
        await _drained!.future;
      }
      return await action();
    } finally {
      _switchDone = null;
      done.complete();
    }
  }
}
