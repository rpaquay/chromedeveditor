// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_channel;

import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/channel/channel.dart';
import 'package:analysis_server/src/protocol.dart';

import 'dart_analysis_logger.dart';

/**
 * The abstract class [ServerCommunicationChannel] defines the behavior of
 * objects that allow an [AnalysisServer] to receive [Request]s and to return
 * both [Response]s and [Notification]s.
 */
typedef void OnRequest(Request request);
typedef void OnDone();

class LocalServerCommunicationChannel implements ServerCommunicationChannel {
  OnRequest _onRequest;
  Function _onError;
  OnDone _onDone;

  void clientSendRequest(Request request) {
    assert(_onRequest != null);
    _onRequest(request);
  }

  /**
   * Listen to the channel for requests. If a request is received, invoke the
   * [onRequest] function. If an error is encountered while trying to read from
   * the socket, invoke the [onError] function. If the socket is closed by the
   * client, invoke the [onDone] function.
   * Only one listener is allowed per channel.
   */
  @override
  void listen(void onRequest(Request request), {Function onError, void onDone()}) {
    // TODO(rpaquay)
    AnalysisLogger.instance.debug("LocalServerCommunicationChannel.listen");
    _onRequest = onRequest;
    _onError = onError;
    _onDone = onDone;
  }

  /**
   * Send the given [notification] to the client.
   */
  @override
  void sendNotification(Notification notification) {
    // TODO(rpaquay)
    AnalysisLogger.instance.debug("LocalServerCommunicationChannel.sendNotification(${notification.event})");
  }

  /**
   * Send the given [response] to the client.
   */
  @override
  void sendResponse(Response response) {
    // TODO(rpaquay)
    AnalysisLogger.instance.debug("LocalServerCommunicationChannel.sendResponse(${response.id})");
  }

  /**
   * Close the communication channel.
   */
  @override
  void close() {
    // TODO(rpaquay)
    AnalysisLogger.instance.debug("LocalServerCommunicationChannel.close");
  }
}
