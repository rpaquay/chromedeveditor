// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.manifest_json_builder;

import 'dart:async';

import 'package:json/json.dart';

import '../builder.dart';
import '../jobs.dart';
import '../workspace.dart';
import '../package_mgmt/bower_properties.dart';

class ManifestJsonProperties {
  final String fileName = "manifest.json";
  final String syntaxMarkerType = "manifest_json.syntax";
  final int syntaxMarkerSeveruty = Marker.SEVERITY_ERROR;
  final String semanticsMarkerType = "manifest_json.semantics";
  final int semanticsMarkerSeverity = Marker.SEVERITY_WARNING;
}

final manifestJsonProperties = new ManifestJsonProperties();

/**
 * A [Builder] implementation to add validation warnings to JSON files.
 */
class ManifestJsonBuilder extends Builder {
  @override
  Future build(ResourceChangeEvent event, ProgressMonitor monitor) {
    Iterable<ChangeDelta> changes = filterPackageChanges(event.changes);
    changes = changes.where((c) => c.resource is File && _shouldProcessFile(c.resource));

    return Future.wait(changes.map((c) => _handleFileChange(c.resource)));
  }

  bool _shouldProcessFile(File file) {
    // There's a more specific builder for bower.
    if (file.name == bowerProperties.packageSpecFileName) return false;

    return file.name == manifestJsonProperties.fileName && !file.isDerived();
  }

  Future _handleFileChange(File file) {
    return file.getContents().then((String str) {
      file.clearMarkers(manifestJsonProperties.syntaxMarkerType);
      file.clearMarkers(manifestJsonProperties.semanticsMarkerType);
      file.createMarker(manifestJsonProperties.semanticsMarkerType, manifestJsonProperties.semanticsMarkerSeverity, "Hello world", 1, 0, 1);

      try {
        if (str.trim().isNotEmpty) {
          JsonParser parser = new JsonParser(str, new _JsonParserListener(file));
          parser.parse();
        }
      } catch (e) {
        // Ignore e; already reported through the listener interface.
      }
    });
  }
}

class _JsonParserListener extends JsonListener {
  final File file;

  _JsonParserListener(this.file);

  void fail(String source, int position, String message) {
    int lineNum = _calcLineNumber(source, position);
    file.createMarker(manifestJsonProperties.syntaxMarkerType, manifestJsonProperties.syntaxMarkerSeveruty, message, lineNum, position);
  }

  /**
   * Count the newlines between 0 and position.
   */
  int _calcLineNumber(String source, int position) {
    // TODO(rpaquay): This is O(n), it could be made O(log n) with a binary search in a sorted array.
    int lineCount = 0;

    for (int index = 0; index < source.length; index++) {
      // TODO(rpaquay): There are other characters to consider as "end of line".
      if (source[index] == '\n') lineCount++;
      if (index == position) return lineCount + 1;
    }

    return lineCount;
  }
}
