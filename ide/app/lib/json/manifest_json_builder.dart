// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.manifest_json_builder;

import 'dart:async';

import 'json_parser.dart';
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

abstract class ErrorEmitter {
  void emitError(Span span, String message);
}

class FileErrorEmitter implements ErrorEmitter {
  final File file;
  final String contents;
  final String markerType;
  final int markerSeverity;

  FileErrorEmitter(this.file, this.contents, this.markerType, this.markerSeverity) {
    file.clearMarkers(markerType);
  }

  void emitError(Span span, String message) {
    int lineNum = _calcLineNumber(contents, span.start);
    file.createMarker(markerType, markerSeverity, message, lineNum, span.start, span.end);
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
    return file.name == manifestJsonProperties.fileName && !file.isDerived();
  }

  Future _handleFileChange(File file) {
    // TODO(rpaquay): The work below should be performed in an isolate to avoid blocking UI.
    return file.getContents().then((String str) {
      ErrorEmitter syntaxErrorEmitter = new FileErrorEmitter(file, str, manifestJsonProperties.syntaxMarkerType, manifestJsonProperties.syntaxMarkerSeveruty);
      ErrorEmitter manifestErrorEmitter = new FileErrorEmitter(file, str, manifestJsonProperties.semanticsMarkerType, manifestJsonProperties.semanticsMarkerSeverity);

      // TODO(rpaquay): Change JsonParser to never throw exception, just report errors and recovers.
      try {
        if (str.trim().isNotEmpty) {
          JsonParser parser = new JsonParser(str, new _JsonParserListener(file, syntaxErrorEmitter, manifestErrorEmitter));
          parser.parse();
        }
      } on FormatException catch (e) {
        // Ignore e; already reported through the listener interface.
      }
    });
  }
}

abstract class Entity {
  Span span;
  Entity();
}

abstract class ValueEntity extends Entity {
  get value;
}

class StringEntity extends ValueEntity {
  String text;
  StringEntity(Span span, this.text) {
    this.span = span;
  }

  get value => this.text;
}

class NullEntity extends ValueEntity {
  NullEntity(Span span) {
    this.span = span;
  }

  get value => null;
}

class NumberEntity extends ValueEntity {
  num number;
  NumberEntity(Span span, this.number) {
    this.span = span;
  }

  get value => this.number;
}

class BoolEntity extends ValueEntity {
  bool boolValue;
  BoolEntity(Span span, this.boolValue) {
    this.span = span;
  }

  get value => this.boolValue;
}

class ArrayEntity extends Entity {
}

class ObjectEntity extends Entity {
}

class _JsonParserListener extends JsonListener {
  final File file;
  final ErrorEmitter syntaxErrorEmitter;
  final ErrorEmitter manifestErrorEmitter;
  List<Entity> entities = new List<Entity>();
  List<Validator> validators = new List<Validator>();

  _JsonParserListener(this.file, this.syntaxErrorEmitter, this.manifestErrorEmitter) {
    validators.add(new RootValidator(manifestErrorEmitter));
  }

  Validator get currentValidator => validators.last;
  Entity get currentEntity => entities.last;

  void handleString(Span span, String value) {
    entities.add(new StringEntity(span, value));
  }
  void handleNumber(Span span, num value) {
    entities.add(new NumberEntity(span, value));
  }
  void handleBool(Span span, bool value) {
    entities.add(new BoolEntity(span, value));
  }
  void handleNull(Span span) {
    entities.add(new NullEntity(span));
  }

  // Called when the ":" is parsed.
  // Invariants: current entity is a string and parent entity a an object
  void propertyName(Span span) {
    StringEntity name = entities.removeLast();
    assert(entities.last is ObjectEntity);
    currentValidator.propertyName(name);
  }

  // Called when the value after ":" is parsed.
  // Invariants: current entity is the property value and the parent is an EntityObject.
  void propertyValue(Span span) {
    Entity value = entities.removeLast();
    assert(entities.last is ObjectEntity);
    currentValidator.propertyValue(value);
  }

  // Called when the opening "{" of an object is parsed.
  void beginObject(int position) {
    entities.add(new ObjectEntity());
    Validator validator = currentValidator.enterObject();
    validators.add(validator);
  }

  // Called when the closing "}" of an object is parsed.
  // Invariants: current entity is the ObjectEntity.
  void endObject(Span span) {
    ObjectEntity object = entities.removeLast();
    assert(object is ObjectEntity);
    object.span = span;
    currentValidator.leaveObject(object);
    validators.removeLast();
  }

  // Called when the "[" of an array is parsed.
  void beginArray(int position) {
    entities.add(new ArrayEntity());
    Validator validator = currentValidator.enterArray();
    validators.add(validator);
  }

  // Called when the "]" of an array is parsed.
  // Invariants: current entity is the array entity.
  void endArray(Span span) {
    ArrayEntity array = entities.removeLast();
    assert(array is ArrayEntity);
    array.span = span;
    currentValidator.leaveArray(array);
    validators.removeLast();
  }

  // Called when the "," after an array element is parsed.
  // Invariants: current entity is the array element, the parent is an ArrayObject.
  void arrayElement(Span span) {
    Entity value = entities.removeLast();
    assert(entities.last is ArrayEntity);
    currentValidator.arrayElement(value);
  }

  void fail(String source, Span span, String message) {
    syntaxErrorEmitter.emitError(span, message);
  }
}

abstract class Validator {
  Validator enterArray();
  void leaveArray(ArrayEntity array);
  void arrayElement(Entity element);

  Validator enterObject();
  void leaveObject(ObjectEntity object);
  void propertyName(StringEntity name);
  void propertyValue(Entity value);
}

class NullValidator implements Validator {
  Validator enterArray() {
    return this;
  }
  void leaveArray(ArrayEntity array) {}
  void arrayElement(Entity element) {}

  Validator enterObject() {
    return this;
  }
  void leaveObject(ObjectEntity object) {}
  void propertyName(StringEntity name) {}
  void propertyValue(Entity value) {}
}

class RootValidator extends NullValidator {
  final ErrorEmitter errorEmitter;

  RootValidator(this.errorEmitter);

  Validator enterObject() {
    return new TopLevelValidator(errorEmitter);
  }
}

//
// The code below should be auto-generated from a manifest schema definition.
//
class TopLevelValidator extends NullValidator {
  final List<String> known_properties = ["manifest_version", "version"];
  final ErrorEmitter errorEmitter;

  TopLevelValidator(this.errorEmitter);

  Validator enterObject() {
    return new NullValidator();
  }
  Validator enterArray() {
    return new NullValidator();
  }

  void propertyName(StringEntity name) {
    if (!known_properties.contains(name.text)) {
      errorEmitter.emitError(name.span, "Top level property \"" + name.text +"\" is not recognized. Known property names are [" + known_properties.join(", ") + "]");
    }
  }
}
