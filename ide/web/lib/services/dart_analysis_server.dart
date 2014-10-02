// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_server;

import 'dart:async';

import 'package:analyzer_clone/source/package_map_provider.dart';
import 'package:analysis_server/src/analysis_server.dart';
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
import 'dart_analysis_channel.dart';
import 'dart_analysis_file_system.dart';
import 'dart_analysis_package_map_provider.dart';
import 'dart_analysis_project.dart';
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
  final Map<String, ProjectContext> _contexts = {};
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
    _contexts[id] = new ProjectContext(
        id,
        analysisServer,
        dartSdk,
        _contentsProvider,
        _resourceProvider,
        _serverChannel.clientChannel);
    return new Future.value(null);
  }

  @override
  Future<AnalysisResultUuid> processContextChanges(
      String id,
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids) {
    // TODO(rpaquay)
    ProjectContext context = _contexts[id];
    if (context == null) {
      return new Future.error('no context associated with id ${id}');
    }

    return context.processChanges(addedUuids, changedUuids, deletedUuids);
  }

  @override
  Future disposeContext(String id) {
    // TODO(rpaquay): Notify analysis server
    ProjectContext context = _contexts[id];
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
