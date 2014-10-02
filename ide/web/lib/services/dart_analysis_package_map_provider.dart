// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_server;

import 'package:analyzer_clone/file_system/file_system.dart';
import 'package:analyzer_clone/source/package_map_provider.dart';

import 'dart_analysis_file_system.dart';
import 'dart_analysis_logger.dart';

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
    AnalysisLogger.instance.debug("LocalPackageMapProvider.computePackageMap(\"${folder.path}\")");
    // TODO(rpaquay): Compute dependencies!
    if (folder is ProjectRootFolder) {
      var map = folder.getPackageRootFolder().createPackageMap();
      return new PackageMapInfo(map, new Set<String>());
    }
    return new PackageMapInfo({}, new Set<String>());
  }
}
