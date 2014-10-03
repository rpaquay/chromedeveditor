// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_channel;

import 'dart:async';

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

/**
 * Implementation of [ServerCommunicationChannel] for using an [AnalysisServer]
 * instance in the same isolate at the client. The client can communicate with
 * the server by accessing the [clientChannel] property.
 */
class LocalServerCommunicationChannel implements ServerCommunicationChannel {
  // Client state
  ClientCommunicationChannel _clientChannel;
  final StreamController<Notification> _clientNotificationStreamController;
  final StreamController<Response> _clientResponseStreamContoller;
  final Map<String, _RequestEntry> _activeClientRequests = {};

  // Server state
  OnRequest _onRequest;
  Function _onError;
  OnDone _onDone;

  LocalServerCommunicationChannel()
    : _clientNotificationStreamController = new StreamController<Notification>.broadcast(),
      _clientResponseStreamContoller = new StreamController<Response>.broadcast() {
    _clientChannel = new _LocalClientCommunicationChannel(this);
  }

  ClientCommunicationChannel get clientChannel =>
      _clientChannel;

  Stream<Notification> get _clientNotificationStream =>
      _clientNotificationStreamController.stream;

  Stream<Response> get _clientResponseStream =>
      _clientResponseStreamContoller.stream;

  Future<Response> _clientSendRequest(Request request) {
    assert(_onRequest != null);

    // Create and enqueue entry for the request
    assert(_activeClientRequests[request.id] == null);
    _RequestEntry entry = new _RequestEntry(request, new Completer<Response>());
    _activeClientRequests[request.id] = entry;

    // Pass request to the analysis server.
    _onRequest(request);

    return entry.completer.future;
  }

  Future _clientClose() {
    if (_onDone != null) {
      _onDone();
    }
    return new Future.value(null);
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
    AnalysisLogger.instance.debug("LocalServerCommunicationChannel.sendNotification(${notification.event})");
    _clientNotificationStreamController.add(notification);
  }

  /**
   * Send the given [response] to the client.
   */
  @override
  void sendResponse(Response response) {
    AnalysisLogger.instance.debug("LocalServerCommunicationChannel.sendResponse(${response.id})");

    // Complete and remove request corresponding the the response
    assert(_activeClientRequests[response.id] != null);
    _RequestEntry entry = _activeClientRequests.remove(response.id);
    assert(entry != null);
    assert(entry.request.id == response.id);
    entry.completer.complete(response);

    // Push the response to the stream
    _clientResponseStreamContoller.add(response);
  }

  /**
   * Close the communication channel.
   */
  @override
  void close() {
    AnalysisLogger.instance.debug("LocalServerCommunicationChannel.close");
    _activeClientRequests.clear();
    _clientNotificationStreamController.close();
    _clientResponseStreamContoller.close();
  }
}

/**
 * An entry in the client request queue. Used to complete a [Future]
 * when the response with the same ID as the request comes in from the
 * analysis server.
 */
class _RequestEntry {
  final Request request;
  final Completer completer;
  _RequestEntry(this.request, this.completer);
}

/**
 * The abstract class [ClientCommunicationChannel] defines the behavior of
 * objects that allow a client to send [Request]s to an [AnalysisServer] and to
 * receive both [Response]s and [Notification]s.
 * [_LocalClientCommunicationChannel] is the implementation of
 * [ClientCommunicationChannel] used for communicating with a corresponding
 * instance of [LocalServerCommunicationChannel].
 */
class _LocalClientCommunicationChannel implements ClientCommunicationChannel {
  final LocalServerCommunicationChannel _localChannel;

  _LocalClientCommunicationChannel(LocalServerCommunicationChannel localChannel)
    : this._localChannel = localChannel,
      this.notificationStream = localChannel._clientNotificationStream,
      this.responseStream = localChannel._clientResponseStream;

  /**
   * The stream of notifications from the server.
   */
  @override
  Stream<Notification> notificationStream;

  /**
   * The stream of responses from the server.
   */
  @override
  Stream<Response> responseStream;

  /**
   * Send the given [request] to the server
   * and return a future with the associated [Response].
   */
  @override
  Future<Response> sendRequest(Request request) {
    AnalysisLogger.instance.debug("LocalClientCommunicationChannel.sendRequest(${request.id})");
    return _localChannel._clientSendRequest(request);
  }

  /**
   * Close the channel to the server. Once called, all future communication
   * with the server via [sendRequest] will silently be ignored.
   */
  @override
  Future close() {
    return _localChannel._clientClose();
  }
}
