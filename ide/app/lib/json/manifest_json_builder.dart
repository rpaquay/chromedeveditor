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
  final List<Entity> containers = new List<Entity>();
  final List<Validator> validators = new List<Validator>();
  Entity currentContainer;
  Validator currentValidator;
  StringEntity key;
  Entity value;

  _JsonParserListener(this.file, this.syntaxErrorEmitter, this.manifestErrorEmitter) {
    currentValidator = new RootValidator(manifestErrorEmitter); 
  }

  /** Pushes the currently active container (and key, if a [Map]). */
  void pushContainer() {
    if (currentContainer is ObjectEntity) {
      assert(key != null);
      containers.add(key);
    }
    containers.add(currentContainer);
    validators.add(currentValidator);
  }

  /** Pops the top container from the [stack], including a key if applicable. */
  void popContainer() {
    value = currentContainer;
    currentContainer = containers.removeLast();
    if (currentContainer is ObjectEntity) {
      key = containers.removeLast();
    }
    currentValidator = validators.removeLast();
  }
  
  void handleString(Span span, String value) {
    this.value = new StringEntity(span, value);
  }
  void handleNumber(Span span, num value) {
    this.value = new NumberEntity(span, value);
  }
  void handleBool(Span span, bool value) {
    this.value = new BoolEntity(span, value);
  }
  void handleNull(Span span) {
    this.value = new NullEntity(span);
  }

  // Called when the opening "{" of an object is parsed.
  void beginObject(int position) {
    assert(currentValidator != null);
    pushContainer();
    currentContainer = new ObjectEntity();
    currentValidator = currentValidator.enterObject();
  }

  // Called when the closing "}" of an object is parsed.
  void endObject(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ObjectEntity);
    currentContainer.span = span;
    currentValidator.leaveObject(currentContainer);
    popContainer();
  }

  // Called when the opening "[" of an array is parsed.
  void beginArray(int position) {
    assert(currentValidator != null);
    pushContainer();
    currentContainer = new ArrayEntity();
    currentValidator = currentValidator.enterArray();
  }

  // Called when the closing "]" of an array is parsed.
  void endArray(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ArrayEntity);
    currentContainer.span = span;
    currentValidator.leaveArray(currentContainer);
    popContainer();
  }

  // Called when a ":" is parsed inside an object.
  void propertyName(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ObjectEntity);
    assert(value != null);
    assert(value is StringEntity);
    key = value;
    value = null;
    currentValidator.propertyName(key);
  }

  // Called when a "," or "}" is parsed inside an object.
  void propertyValue(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ObjectEntity);
    assert(value != null);
    currentValidator.propertyValue(value);
    key = value = null;
  }

  // Called when the "," after an array element is parsed.
  // Invariants: current entity is the array element, the parent is an ArrayObject.
  void arrayElement(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ArrayEntity);
    assert(value != null);
    currentValidator.arrayElement(value);
    value = null;
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
  // from https://developer.chrome.com/extensions/manifest
  static final List<String> known_properties = [
    "manifest_version",
    "name",
    "version",
    "default_locale",
    "description",
    "icons",
    "browser_action",
    "page_action",
    "author",
    "automation",
    "background",
    "background_page",
    "chrome_settings_overrides",
    "chrome_ui_overrides",
    "chrome_url_overrides",
    "commands",
    "content_pack",
    "content_scripts",
    "content_security_policy",
    "converted_from_user_script",
    "current_locale",
    "devtools_page",
    "externally_connectable",
    "file_browser_handlers",
    "homepage_url",
    "import",
    "incognito",
    "input_components",
    "key",
    "minimum_chrome_version",
    "nacl_modules",
    "oauth2",
    "offline_enabled",
    "omnibox",
    "optional_permissions",
    "options_page",
    "page_actions",
    "permissions",
    "platforms",
    "plugins",
    "requirements",
    "sandbox",
    "script_badge",
    "short_name",
    "signature",
    "spellcheck",
    "storage",
    "system_indicator",
    "tts_engine",
    "update_url",
    "web_accessible_resources",
    ];
  
  // from https://developer.chrome.com/apps/manifest
  static final List<String> known_properties_apps = [
    "app",                                              
    "manifest_version",
    "name",
    "version",
    "default_locale",
    "description",
    "icons",
    "author",
    "bluetooth",
    "commands",
    "current_locale",
    "externally_connectable",
    "file_handlers",
    "import",
    "key",
    "kiosk_enabled",
    "kiosk_only",
    "minimum_chrome_version",
    "nacl_modules",
    "oauth2",
    "offline_enabled",
    "optional_permissions",
    "permissions",
    "platforms",
    "requirements",
    "sandbox",
    "short_name",
    "signature",
    "sockets",
    "storage",
    "system_indicator",
    "update_url",
    "url_handlers",
    "webview",
    ];
  
  static final Set<String> allProperties = known_properties.toSet().union(known_properties_apps.toSet());

  final ErrorEmitter errorEmitter;

  TopLevelValidator(this.errorEmitter);

  Validator enterObject() {
    return new NullValidator();
  }
  
  Validator enterArray() {
    return new NullValidator();
  }

  void propertyName(StringEntity name) {
    if (!allProperties.contains(name.text)) {
      // TODO(rpaquay): Adding the list of known property names currently makes the error tooltip too big and messes up the UI.
      //String message = "Top level property \"${name.text}\" is not recognized. Known property names are [" + allProperties.join(", ") + "]");
      String message = "Top level property \"${name.text}\" is not recognized.";
      errorEmitter.emitError(name.span, message);
    }
  }
}
