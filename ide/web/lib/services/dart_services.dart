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
  Future<ServiceActionEvent> processContextChanges(
      String contextId,
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids);

  /**
   * Dispose all resources for the given context [contextId].
   */
  Future disposeContext(String id);

  /**
   * Returns a [Declaration] (or `null`) corresponding to the declaration in the
   * source files [fileUuid] at [offset].
   */
  Declaration getDeclarationFor(String contextId, String fileUuid, int offset);

  /**
   * Returns a mapping from file uuids to list of errors for the list of files
   * [fileUuids].
   */
  Future<Map<String, List<Map>>> buildFiles(List<Map> fileUuids);
}
