// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_services;

import 'dart:async';

import 'services_common.dart';

/**
 * Abstraction over a set of services for Dart source files.
 */
abstract class DartServices {
  /**
   * Return an [Outline] instance for a given source file [codeString].
   */
  Future<Outline> getOutlineFor(String codeString);

  /**
   * Create a new project context with the given [id].
   */
  Future createContext(String id);

  /**
   * Adds/changes/removes files from the given context [contextId].
   */
  Future<AnalysisResultUuid> processContextChanges(
      String contextId,
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids);

  /**
   * Dispose all resources for the given context [contextId].
   */
  Future disposeContext(String contextId);

  /**
   * Returns a [Declaration] (or `null`) corresponding to the declaration in the
   * source files [fileUuid] at [offset].
   */
  Future<Declaration> getDeclarationFor(String contextId, String fileUuid, int offset);
}

class AnalysisResultUuid {
  /**
   * A Map from file uuids to list of associated errors.
   */
  final Map<String, List<AnalysisError>> _errorMap = {};

  AnalysisResultUuid();

  void addErrors(String uuid, List<AnalysisError> errors) {
    // Ignore warnings from imported packages.
    if (!uuid.startsWith('package:')) {
      _errorMap[uuid] = errors;
    }
  }

  Map toMap() {
    Map m = {};
    _errorMap.forEach((String uuid, List<AnalysisError> errors) {
      m[uuid] = errors.map((e) => e.toMap()).toList();
    });
    return m;
  }
}
