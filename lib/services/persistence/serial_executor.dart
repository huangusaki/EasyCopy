import 'dart:async';

/// Orders asynchronous operations without letting one failure poison the queue.
class SerialExecutor {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(FutureOr<T> Function() action) {
    final Future<T> result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
