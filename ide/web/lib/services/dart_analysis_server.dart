// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_server;

import 'dart:async';

import 'package:analyzer_clone/file_system/file_system.dart';
import 'package:analyzer_clone/source/package_map_provider.dart';
import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/channel/channel.dart';
import 'package:analysis_server/src/protocol.dart';
import 'package:analysis_server/src/services/index/index.dart';
import 'package:analysis_server/src/services/index/local_memory_index.dart' as memory_index;
import 'package:path/src/context.dart';

import '../dart/sdk.dart' as sdk;
import 'chrome_dart_sdk.dart';
import 'dart_analyzer.dart' as dart_analyzer;
import 'dart_services.dart';
import 'outline_builder.dart';
import 'services_common.dart' as common;

/**
 * Implementation of [DartServices] using the [analysis_server] package.
 */
class AnalysisServerDartServices implements DartServices {
  final ChromeDartSdk dartSdk;
  final common.ContentsProvider _contentsProvider;
  final Map<String, AnalysisServerProjectContext> _contexts = {};
  AnalysisServer analysisServer;

  AnalysisServerDartServices(sdk.DartSdk sdk, this._contentsProvider)
    : dartSdk = createSdk(sdk) {

    // TODO(rpaquay): Using an in-memory index is the easiest thing, but we would
    // ideally store the index to some persistent store to re-use accross sessions.
    Index index = memory_index.createLocalMemoryIndex();
    ServerCommunicationChannel channel = new LocalServerCommunicationChannel();
    ResourceProvider resourceProvider = new LocalResourceProvider();
    PackageMapProvider packageMapProvider = new LocalPackageMapProvider();
    analysisServer = new AnalysisServer(
        channel,
        resourceProvider,
        packageMapProvider,
        index,
        dartSdk);
  }

  //Future<ChromeDartSdk> get dartSdkFuture => new Future.value(dartSdk);

  @override
  Future<common.Outline> getOutlineFor(String codeString) {
    return dart_analyzer
        .analyzeString(dartSdk, codeString)
        .then((dart_analyzer.AnalyzerResult result) {
          return new OutlineBuilder().build(result.ast);
        });
  }

  @override
  Future createContext(String id) {
    // TODO(rpaquay): Notify analysis server
    _contexts[id] = new AnalysisServerProjectContext(id, dartSdk, _contentsProvider);
    return new Future.value(null);
  }

  @override
  Future<AnalysisResultUuid> processContextChanges(
      String id,
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids) {
    // TODO(rpaquay)
    AnalysisServerProjectContext context = _contexts[id];
    if (context == null) {
      return new Future.error('no context associated with id ${id}');
    }

    return context.processChanges(addedUuids, changedUuids, deletedUuids);
  }

  @override
  Future disposeContext(String id) {
    // TODO(rpaquay): Notify analysis server
    AnalysisServerProjectContext context = _contexts[id];
    if (context == null) {
      return new Future.error('no context associated with id ${id}');
    }
    context.dispose();
    _contexts.remove(id);
    return new Future.value(null);
  }

  @override
  Future<common.Declaration> getDeclarationFor(String contextId, String fileUuid, int offset) {
    // TODO(rpaquay)
    return new Future.value(null);
  }
}

class AnalysisServerProjectContext {
  // The id for the project this context is associated with.
  final String id;
  final AnalysisServer analysisServer;
  final ChromeDartSdk sdk;
  final common.ContentsProvider provider;
  /// 'true' if the corresponding context has been added to the analysisServer
  bool contextCreated;

  AnalysisServerProjectContext(this.id, this.analysisServer, this.sdk, this.provider) {
//    AnalysisEngine.instance.logger = new _AnalysisEngineDebugLogger();
//    context = AnalysisEngine.instance.createAnalysisContext();
//    context.sourceFactory = new SourceFactory([
//        new DartSdkUriResolver(sdk),
//        new PackageUriResolver(this),
//        new FileUriResolver(this)
//    ]);
  }

  Future<AnalysisResultUuid> processChanges(
      String id,
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids) {
    analysisServer.contextDirectoryManager.addContext(folder, packageMap);
    analysisServer.getAnalysisContext(path);
    return new Future.value(null);
  }

  void dispose() {
    // TODO(rpaquay): Notify analysis server
  }
}

/**
 * The abstract class [ServerCommunicationChannel] defines the behavior of
 * objects that allow an [AnalysisServer] to receive [Request]s and to return
 * both [Response]s and [Notification]s.
 */
class LocalServerCommunicationChannel implements ServerCommunicationChannel {
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
  }

  /**
   * Send the given [notification] to the client.
   */
  @override
  void sendNotification(Notification notification) {
    // TODO(rpaquay)
  }

  /**
   * Send the given [response] to the client.
   */
  @override
  void sendResponse(Response response) {
    // TODO(rpaquay)
  }

  /**
   * Close the communication channel.
   */
  @override
  void close() {
    // TODO(rpaquay)
  }
}

/**
 * Instances of the class [ResourceProvider] convert [String] paths into
 * [Resource]s.
 */
class LocalResourceProvider implements ResourceProvider {
  /**
   * Get the path context used by this resource provider.
   */
  @override
  final Context pathContext;

  LocalResourceProvider(): this.pathContext = new Context();

  /**
   * Return the [Resource] that corresponds to the given [path].
   */
  @override
  Resource getResource(String path) {
    // TODO(rpaquay)
    return null;
  }
}

/**
 * A PackageMapProvider is an entity capable of determining the mapping from
 * package name to source directory for a given folder.
 */
class LocalPackageMapProvider implements PackageMapProvider {
  /**
   * Compute a package map for the given folder, if possible.
   *
   * If a package map can't be computed (e.g. because an error occurred), a
   * [PackageMapInfo] will still be returned, but its packageMap will be null.
   */
  @override
  PackageMapInfo computePackageMap(Folder folder) {
    // TODO(rpaquay)
    return null;
  }
}
