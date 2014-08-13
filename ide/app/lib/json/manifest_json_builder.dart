// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.manifest_json_builder;

import 'dart:async';

import 'json_parser.dart';
import 'json_validator.dart';
import 'manifest_json_validator.dart';
import 'utils.dart';
import '../builder.dart';
import '../jobs.dart';
import '../workspace.dart';

class ManifestJsonProperties {
  final String fileName = "manifest.json";
  final String syntaxMarkerType = "manifest_json.syntax";
  final int syntaxMarkerSeveruty = Marker.SEVERITY_ERROR;
  final String semanticsMarkerType = "manifest_json.semantics";
  final int semanticsMarkerSeverity = Marker.SEVERITY_WARNING;
}

final manifestJsonProperties = new ManifestJsonProperties();

/**
 * A [Builder] implementation to add validation warnings to "manifest.json" files.
 */
class ManifestJsonBuilder extends Builder {
  @override
  Future build(ResourceChangeEvent event, ProgressMonitor monitor) {
    Iterable<ChangeDelta> changes = filterPackageChanges(event.changes);
    changes = changes.where((c) => c.resource is File && _shouldProcessFile(c.resource));

    return Future.wait(changes.map((c) => _handleFileChange(c.resource)));
  }

  bool _shouldProcessFile(File file) {
    return file.name == manifestJsonProperties.fileName && !file.isDerived();
  }

  Future _handleFileChange(File file) {
    // TODO(rpaquay): The work below should be performed in an isolate to avoid blocking UI.
    return file.getContents().then((String str) {
      ErrorSink syntaxErrorSink = new FileErrorSink(file, str, manifestJsonProperties.syntaxMarkerType, manifestJsonProperties.syntaxMarkerSeveruty);
      ErrorSink manifestErrorSink = new FileErrorSink(file, str, manifestJsonProperties.semanticsMarkerType, manifestJsonProperties.semanticsMarkerSeverity);

      // TODO(rpaquay): Change JsonParser to never throw exception, just report errors and recovers.
      try {
        // TODO(rpaquay): Should we report errors if the file is empty?
        if (str.trim().isNotEmpty) {
          JsonEntityValidatorListener listener = new JsonEntityValidatorListener(syntaxErrorSink, new RootValidator(manifestErrorSink));
          JsonParser parser = new JsonParser(str, listener);
          parser.parse();
        }
      } on FormatException catch (e) {
        // Ignore e; already reported through the listener interface.
      }
    });
  }
}
