// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.analysis_server;

import 'dart:async';

//import 'package:analyzer/file_system/file_system.dart';
//import 'package:analysis_server/src/analysis_server.dart';
//import 'package:analysis_server/src/channel/channel.dart';
//import 'package:analysis_server/src/package_map_provider.dart';
//import 'package:analysis_server/src/services/index/index.dart';

import '../dart/sdk.dart' as sdk;
import 'chrome_dart_sdk.dart';
import 'dart_services.dart';
import 'services_common.dart' as common;

/**
 * Implementation of [DartServices] using the [analysis_server] package.
 */
class AnalysisServerDartServices implements DartServices {
  final ChromeDartSdk dartSdk;
  final common.ContentsProvider _contentsProvider;
  //final Map<String, ProjectContext> _contexts = {};

  AnalysisServerDartServices(sdk.DartSdk sdk, this._contentsProvider)
    : dartSdk = createSdk(sdk) {
//    ServerCommunicationChannel channel = null;
//    ResourceProvider resourceProvider = null;
//    PackageMapProvider packageMapProvider = null;
//    Index index = null;
//    AnalysisServer server = new AnalysisServer(
//        channel,
//        null, //resourceProvider,
//        packageMapProvider,
//        index,
//        dartSdk);
  }

  //Future<ChromeDartSdk> get dartSdkFuture => new Future.value(dartSdk);

  @override
  Future<common.Outline> getOutlineFor(String codeString) {
    return new Future.value(null);
  }

  @override
  Future createContext(String id) {
    return new Future.value(null);
  }

  @override
  Future<AnalysisResultUuid> processContextChanges(
      String id,
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids) {
    return new Future.value(null);
  }

  @override
  Future disposeContext(String id) {
    return new Future.value(null);
  }

  @override
  Future<common.Declaration> getDeclarationFor(String contextId, String fileUuid, int offset) {
    return new Future.value(null);
  }
}
