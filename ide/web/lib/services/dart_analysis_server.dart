// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_server;

import 'dart:async';

import 'package:analyzer_clone/source/package_map_provider.dart';
import 'package:analyzer_clone/src/generated/engine.dart';
import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/channel/channel.dart';
import 'package:analysis_server/src/protocol.dart';
import 'package:analysis_server/src/services/index/index.dart';
import 'package:analysis_server/src/services/index/local_memory_index.dart' as memory_index;
import 'package:analysis_server/src/domain_analysis.dart';
import 'package:analysis_server/src/domain_completion.dart';
import 'package:analysis_server/src/edit/edit_domain.dart';
import 'package:analysis_server/src/search/search_domain.dart';
import 'package:analysis_server/src/domain_execution.dart';
import 'package:analysis_server/src/domain_server.dart';

import '../dart/sdk.dart' as sdk;
import 'chrome_dart_sdk.dart';
import 'dart_analyzer.dart' as dart_analyzer;
import 'dart_analysis_file_system.dart';
import 'dart_analysis_logger.dart';
import 'dart_analysis_package_map_provider.dart';
import 'dart_services.dart';
import 'dart_source.dart';
import 'outline_builder.dart';
import 'services_common.dart' as common;

/**
 * Implementation of [DartServices] using the [analysis_server] package.
 */
class AnalysisServerDartServices implements DartServices {
  final ChromeDartSdk dartSdk;
  final ContentsProvider _contentsProvider;
  final LocalResourceProvider _resourceProvider;
  final LocalServerCommunicationChannel _serverChannel;
  final Map<String, AnalysisServerProjectContext> _contexts = {};
  AnalysisServer analysisServer;

  AnalysisServerDartServices(sdk.DartSdk sdk, this._contentsProvider)
    : dartSdk = createSdk(sdk),
      _resourceProvider = new LocalResourceProvider(),
      _serverChannel = new LocalServerCommunicationChannel() {

    // TODO(rpaquay): Using an in-memory index is the easiest thing, but we would
    // ideally store the index to some persistent store to re-use accross sessions.
    Index index = memory_index.createLocalMemoryIndex();
    PackageMapProvider packageMapProvider = new LocalPackageMapProvider();
    analysisServer = new AnalysisServer(
        _serverChannel,
        _resourceProvider,
        packageMapProvider,
        index,
        dartSdk);

    _initializeHandlers(analysisServer);
  }

  /**
   * Initialize the handlers to be used by the given [server].
   */
  void _initializeHandlers(AnalysisServer server) {
    server.handlers = [
        new ServerDomainHandler(server),
        new AnalysisDomainHandler(server),
        new EditDomainHandler(server),
        new SearchDomainHandler(server),
        new CompletionDomainHandler(server),
        new ExecutionDomainHandler(server),
    ];
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
    ProjectState state = new ProjectState(id);
    _contexts[id] = new AnalysisServerProjectContext(
        state,
        analysisServer,
        dartSdk,
        _contentsProvider,
        _resourceProvider,
        _serverChannel);
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

class ProjectState extends ProjectFiles {
  /** The project ID from the editor in the format: "cde-app-id:project-name" */
  final String _id;
  /** file uuid => [WorkspaceSource] */
  final Map<String, WorkspaceSource> _sources = {};

  ProjectState(this._id) {
    assert(FileUuidHelpers.isProjectId(_id));
  }

  Map<String, WorkspaceSource> get sources => _sources;

  @override
  String get projectId => _id;

  @override
  String get rootPath => FileUuidHelpers.getProjectIdProjectPath(_id);

  /** Returns the list of all files included in the project */
  Iterable<WorkspaceSource> get allFiles => _sources.values;
}

/**
 * The context associated to a project.
 */
class AnalysisServerProjectContext {
  // The id for the project this context is associated with.
  final ProjectState _state;
  final AnalysisServer analysisServer;
  final ChromeDartSdk sdk;
  final ContentsProvider contentsProvider;
  final LocalResourceProvider resourceProvider;
  final LocalServerCommunicationChannel serverChannel;
  /// 'true' if the corresponding context has been added to the analysisServer
  bool contextCreated = false;
  ProjectRootFolder projectFolder;

  AnalysisServerProjectContext(
      this._state,
      this.analysisServer,
      this.sdk,
      this.contentsProvider,
      this.resourceProvider,
      this.serverChannel);

  Future<AnalysisResultUuid> processChanges(
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids) {
    // Create the analysis context only for the very first change notification.
    if (!contextCreated) {
      // TODO(rpaquay): Enqueue the request if there are pending ones.
      ChangeSet changeSet = new ChangeSet();
      DartAnalyzerHelpers.processChanges(addedUuids, changedUuids, deletedUuids, changeSet, _state.sources);

      DartAnalyzerHelpers.populateSources(_state._id, _state.sources, contentsProvider).then((_) {
        ProjectRootFolder projectFolder = _createProjectFolder(addedUuids);

        Request request = new AnalysisSetAnalysisRootsParams([projectFolder.path],
            []).toRequest('0');
        handleSuccessfulRequest(request);

        //analysisServer.contextDirectoryManager.addContext(projectFolder, packageMap);
        contextCreated = true;
      });
      // TODO(rpaquay)
      return new Completer().future;
    } else {
      return new Future.value(null);
    }
  }

  void handleSuccessfulRequest(Request request) {
    this.serverChannel.clientSendRequest(request);
  }

  ProjectRootFolder _createProjectFolder(List<String> uuids) {
    List<String> appFiles = uuids.where((String uuid) => FileUuidHelpers.isAppFile(uuid)).toList();
    assert(appFiles.length >= 0);
    String rootFolder = appFiles.map((String uuid) => FileUuidHelpers.getAppFileProjectPath(uuid)).toSet().single;

    // Create folder
    return resourceProvider.addFolder(_state);
  }

  void dispose() {
    // TODO(rpaquay): Clear all pending requests, then notity analysis server
    resourceProvider.removeProject(projectFolder);
  }
}

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
