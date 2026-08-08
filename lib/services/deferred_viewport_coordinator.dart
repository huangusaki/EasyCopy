import 'package:flutter/foundation.dart';

@immutable
class DeferredViewportTicket {
  const DeferredViewportTicket({
    required this.requestId,
    required this.interactionEpoch,
  });

  final int requestId;
  final int interactionEpoch;
}

class DeferredViewportCoordinator {
  int _requestId = 0;
  int _interactionEpoch = 0;

  DeferredViewportTicket beginRequest() {
    _requestId += 1;
    return DeferredViewportTicket(
      requestId: _requestId,
      interactionEpoch: _interactionEpoch,
    );
  }

  void noteUserInteraction() {
    _interactionEpoch += 1;
  }

  bool isActive(DeferredViewportTicket ticket) {
    return ticket.requestId == _requestId &&
        ticket.interactionEpoch == _interactionEpoch;
  }

  bool isLatestRequest(DeferredViewportTicket ticket) {
    return ticket.requestId == _requestId;
  }
}
