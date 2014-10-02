// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_project;

import 'dart:async';

import 'package:analyzer_clone/src/generated/engine.dart';
import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/protocol.dart';

import 'chrome_dart_sdk.dart';
import 'dart_analysis_channel.dart';
import 'dart_analysis_file_system.dart';
import 'dart_services.dart';
import 'dart_source.dart';

/**
 * The context associated to a project.
 */
class AnalysisServerProjectContext {
  // The id for the project this context is associated with.
  final ProjectState _projectState;
  final AnalysisServer _analysisServer;
  final ChromeDartSdk _sdk;
  final ContentsProvider _contentsProvider;
  final LocalResourceProvider _resourceProvider;
  final LocalServerCommunicationChannel _serverChannel;
  /// 'true' if the corresponding context has been added to the analysisServer
  bool contextCreated = false;
  ProjectRootFolder projectFolder;

  AnalysisServerProjectContext(
      this._projectState,
      this._analysisServer,
      this._sdk,
      this._contentsProvider,
      this._resourceProvider,
      this._serverChannel);

  Future<AnalysisResultUuid> processChanges(
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids) {
    // Create the analysis context only for the very first change notification.
    if (!contextCreated) {
      // TODO(rpaquay): Enqueue the request if there are pending ones.
      ChangeSet changeSet = new ChangeSet();
      DartAnalyzerHelpers.processChanges(addedUuids, changedUuids, deletedUuids, changeSet, _projectState.sources);

      DartAnalyzerHelpers.populateSources(_projectState._id, _projectState.sources, _contentsProvider).then((_) {
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
    this._serverChannel.clientSendRequest(request);
  }

  ProjectRootFolder _createProjectFolder(List<String> uuids) {
    List<String> appFiles = uuids.where((String uuid) => FileUuidHelpers.isAppFile(uuid)).toList();
    assert(appFiles.length >= 0);
    String rootFolder = appFiles.map((String uuid) => FileUuidHelpers.getAppFileProjectPath(uuid)).toSet().single;

    // Create folder
    return _resourceProvider.addFolder(_projectState);
  }

  void dispose() {
    // TODO(rpaquay): Clear all pending requests, then notity analysis server
    _resourceProvider.removeProject(projectFolder);
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
