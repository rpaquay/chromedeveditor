// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_project;

import 'dart:async';

import 'package:analyzer_clone/src/generated/engine.dart';
import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/channel/channel.dart';
import 'package:analysis_server/src/protocol.dart';

import 'chrome_dart_sdk.dart';
import 'dart_analysis_file_system.dart';
import 'dart_services.dart';
import 'dart_source.dart';
import 'services_common.dart' as common;

/**
 * The context associated to a project.
 */
class ProjectContext {
  // The id for the project this context is associated with.
  final ProjectState _projectState;
  final AnalysisServer _analysisServer;
  final ChromeDartSdk _sdk;
  final ContentsProvider _contentsProvider;
  final LocalResourceProvider _resourceProvider;
  final ClientCommunicationChannel _clientChannel;
  /// The root folder is lazily created on the first [processchanges]
  ProjectRootFolder _projectFolder;
  bool _contextCreated = false;
  int _requestId = 0;

  ProjectContext(
      String projectId,
      this._analysisServer,
      this._sdk,
      this._contentsProvider,
      this._resourceProvider,
      this._clientChannel)
      : this._projectState = new ProjectState(projectId);

  Future<AnalysisResultUuid> processChanges(
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids) {
    // Create the analysis context only for the very first change notification.
    if (!_contextCreated) {
      _projectFolder = _resourceProvider.addFolder(_projectState);
      _contextCreated = true;

      ChangeSet changeSet = new ChangeSet();
      DartAnalyzerHelpers.processChanges(addedUuids, changedUuids, deletedUuids, changeSet, _projectState.sources);

      Map<String, String> fileUuidFromRequestId = {};
      return DartAnalyzerHelpers
          .populateSources(_projectState._id, _projectState.sources, _contentsProvider)
          .then((_) {
            // We have source files, tell analysis server about them
            Request request = new AnalysisSetAnalysisRootsParams([_projectFolder.path],
                []).toRequest(_createRequestId());
            return _clientChannel.sendRequest(request);
          }).then((_) {
            // Initial analysis is done, ask server for errors for all files
            var futures = _projectState.projectFiles
              .where((source) => FileUuidHelpers.isDartSource(source.uuid))
              .map((source) {
                String sourcePath = source.fullName;
                Request request = new AnalysisGetErrorsParams(sourcePath)
                  .toRequest(_createRequestId());
                fileUuidFromRequestId[request.id] = source.uuid;
                return _clientChannel.sendRequest(request);
              });

            return Future.wait(futures);
          }).then((List<Response> responses) {
            AnalysisResultUuid analysisResult = new AnalysisResultUuid();
            responses.forEach((Response response) {
              AnalysisGetErrorsResult responseResult = new AnalysisGetErrorsResult.fromResponse(response);
              String uuid = fileUuidFromRequestId[response.id];
              assert(uuid != null);
              var errors = responseResult.errors.map((AnalysisError analysisError) {
                common.AnalysisError error = new common.AnalysisError();
                error.offset = analysisError.location.offset;
                error.message = analysisError.message;
                error.lineNumber = analysisError.location.startLine;
                error.length = analysisError.location.length;
                error.errorSeverity =
                    analysisError.severity == AnalysisErrorSeverity.INFO ? common.ErrorSeverity.INFO :
                    analysisError.severity == AnalysisErrorSeverity.WARNING ? common.ErrorSeverity.WARNING :
                    analysisError.severity == AnalysisErrorSeverity.ERROR ? common.ErrorSeverity.ERROR :
                    common.ErrorSeverity.NONE;
                return error;
              });
              analysisResult.addErrors(uuid,  errors.toList());
            });
            return new Future.value(analysisResult);
          });
    } else {
      return new Future.value(null);
    }
  }

  String _createRequestId() {
    _requestId++;
    return _requestId.toString();
  }

  void dispose() {
    // TODO(rpaquay): Clear all pending requests, then notity analysis server
    _resourceProvider.removeProject(_projectFolder);
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
