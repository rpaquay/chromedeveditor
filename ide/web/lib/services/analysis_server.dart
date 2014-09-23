// Copyright (c) 2013, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * This library is an entry-point to the Dart analyzer package.
 */
library spark.analysis_server;

import 'dart:async';

import 'package:analysis_server/src/analysis_server.dart';

import 'services_common.dart' as common;
import 'dart_services.dart';
import '../dart/sdk.dart' as sdk;

/**
 * Implementation of [DartServices] using the [analysis_server] package.
 */
class AnalysisServerDartServices implements DartServices {
  //final ChromeDartSdk dartSdk;
  final common.ContentsProvider _contentsProvider;
  //final Map<String, ProjectContext> _contexts = {};

  AnalysisServerDartServices(sdk.DartSdk sdk, this._contentsProvider) {
  //: dartSdk = createSdk(sdk);

    //TODO (rpaquay)
    //ServerCommunicationChannel channel = null;
    //AnalysisServer server = new AnalysisServer(
    //    );
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
