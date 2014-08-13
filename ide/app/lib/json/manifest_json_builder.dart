// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.manifest_json_builder;

import 'dart:async';

import 'json_parser.dart';
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

// Abstraction over an error reporting mechanism that understands error
// spans and messages.
abstract class ErrorSink {
  void emitMessage(Span span, String message);
}

// Implement of ErrorSink for a [File] instance.
class FileErrorSink implements ErrorSink {
  final File file;
  final String contents;
  final String markerType;
  final int markerSeverity;
  List<int> lineOffsets;

  FileErrorSink(this.file, this.contents, this.markerType, this.markerSeverity) {
    file.clearMarkers(markerType);
  }

  void emitMessage(Span span, String message) {
    int lineNum = _calcLineNumber(contents, span.start) + 1;
    file.createMarker(markerType, markerSeverity, message, lineNum, span.start, span.end);
  }

  /**
   * Count the newlines between 0 and position.
   */
  int _calcLineNumber(String source, int position) {
    if (lineOffsets == null)
      lineOffsets = _createLineOffsets(source);
    
    // Binary search
    int lineNumber = _binarySearch(lineOffsets, position);
    if (lineNumber < 0)
      lineNumber = (~lineNumber) - 1;
    return lineNumber;
  }
  
  static int _binarySearch(List items, var item) {
    int cur = 0;
    int max = items.length;
    while (cur <= max) {
      int med = (cur + max) ~/ 2;
      if (items[med] < item)
        cur = med + 1;
      else if (items[med] > item)
        max = med - 1;
      else
        return med;
    }
    return ~cur;
  }
  
  // TODO(rpaquay): This should be part of [File] maybe?
  static List<int> _createLineOffsets(String source) {
    List<int> result = new List<int>();
    result.add(0);  // first line always starts at offset 0
    
    for (int index = 0; index < source.length; index++) {
      // TODO(rpaquay): There are other characters to consider as "end of line".
      if (source[index] == '\n') {
        result.add(index + 1);
      }
    }
    return result;
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
      ErrorSink syntaxErrorEmitter = new FileErrorSink(file, str, manifestJsonProperties.syntaxMarkerType, manifestJsonProperties.syntaxMarkerSeveruty);
      ErrorSink manifestErrorEmitter = new FileErrorSink(file, str, manifestJsonProperties.semanticsMarkerType, manifestJsonProperties.semanticsMarkerSeverity);

      // TODO(rpaquay): Change JsonParser to never throw exception, just report errors and recovers.
      try {
        if (str.trim().isNotEmpty) {
          _JsonEntityValidatorListener listener = new _JsonEntityValidatorListener(syntaxErrorEmitter, new RootValidator(manifestErrorEmitter));
          JsonParser parser = new JsonParser(str, listener);
          parser.parse();
        }
      } on FormatException catch (e) {
        // Ignore e; already reported through the listener interface.
      }
    });
  }
}

class _JsonEntityValidatorListener extends JsonListener {
  final ErrorSink syntaxErrorEmitter;
  final List<ContainerEntity> containers = new List<ContainerEntity>();
  final List<StringEntity> keys = new List<StringEntity>();
  final List<JsonEntityValidator> validators = new List<JsonEntityValidator>();
  ContainerEntity currentContainer;
  JsonEntityValidator currentValidator;
  StringEntity key;
  JsonEntity value;

  _JsonEntityValidatorListener(this.syntaxErrorEmitter, this.currentValidator);

  /** Pushes the currently active container (and key, if a [Map]). */
  void pushContainer() {
    if (currentContainer is ObjectEntity) {
      assert(key != null);
      keys.add(key);
    }
    containers.add(currentContainer);
  }

  /** Pops the top container from the [stack], including a key if applicable. */
  void popContainer() {
    value = currentContainer;
    currentContainer = containers.removeLast();
    if (currentContainer is ObjectEntity) {
      key = keys.removeLast();
    }
  }
  
  void pushValidator() {
    validators.add(currentValidator);
  }

  void popValidator() {
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
    pushValidator();
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
    popValidator();
  }

  // Called when the opening "[" of an array is parsed.
  void beginArray(int position) {
    assert(currentValidator != null);
    pushContainer();
    pushValidator();
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
    popValidator();
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
    pushValidator();
    currentValidator = currentValidator.propertyName(key);
  }

  // Called when a "," or "}" is parsed inside an object.
  void propertyValue(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ObjectEntity);
    assert(value != null);
    currentValidator.propertyValue(value);
    popValidator();
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
    syntaxErrorEmitter.emitMessage(span, message);
  }
}


// Abstract base class of all types of json entities that are parsed 
// and exposed with a [Span].
abstract class JsonEntity {
  Span span;
}

// Abstract base class for simple values.
abstract class ValueEntity extends JsonEntity {
  get value;
}

// Abstract base class for containers (array and object).
abstract class ContainerEntity extends JsonEntity {
}

// Entity for string values.
class StringEntity extends ValueEntity {
  String text;
  StringEntity(Span span, this.text) {
    this.span = span;
  }

  get value => this.text;
}

// Entity for "null" literal values.
class NullEntity extends ValueEntity {
  NullEntity(Span span) {
    this.span = span;
  }

  get value => null;
}

// Entity for numeric values.
class NumberEntity extends ValueEntity {
  num number;
  NumberEntity(Span span, this.number) {
    this.span = span;
  }

  get value => this.number;
}

// Entity for "true" or "false" literal values.
class BoolEntity extends ValueEntity {
  bool boolValue;
  BoolEntity(Span span, this.boolValue) {
    this.span = span;
  }

  get value => this.boolValue;
}

// Entity for array values.
class ArrayEntity extends ContainerEntity {
}

// Entity for object values.
class ObjectEntity extends ContainerEntity {
}

// Event based interface of a json validator.
abstract class JsonEntityValidator {
  // Invoked when entering an array
  JsonEntityValidator enterArray();
  // Invoked when leaving an array
  void leaveArray(ArrayEntity array);
  // Invoked after parsing an array value
  void arrayElement(JsonEntity element);

  // Invoked when entering an object
  JsonEntityValidator enterObject();
  // Invoked when leaving an object
  void leaveObject(ObjectEntity object);
  // Invoked after parsing an property name inside an object
  JsonEntityValidator propertyName(StringEntity name);
  // Invoked after parsing a propery value inside an object
  void propertyValue(JsonEntity value);
}

// No-op base implementation of a [Validator]. 
class NullValidator implements JsonEntityValidator {
  static final instance = new NullValidator();
  JsonEntityValidator enterArray() { return instance; }
  void leaveArray(ArrayEntity array) {}
  void arrayElement(JsonEntity element) {}

  JsonEntityValidator enterObject() { return instance; }
  void leaveObject(ObjectEntity object) {}
  JsonEntityValidator propertyName(StringEntity name) { return instance; }
  void propertyValue(JsonEntity value) {}
}

// Initial validator for manifest.json contents.
class RootValidator extends NullValidator {
  final ErrorSink errorEmitter;

  RootValidator(this.errorEmitter);

  JsonEntityValidator enterObject() {
    return new TopLevelValidator(errorEmitter);
  }
}

/////////////////////////////////////////////////////////////////////////////
// The code below should be auto-generated from a manifest schema definition.
//

// Validator for the top -level object a manifest.json
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

  final ErrorSink errorEmitter;

  TopLevelValidator(this.errorEmitter);

  JsonEntityValidator propertyName(StringEntity name) {
    if (!allProperties.contains(name.text)) {
      // TODO(rpaquay): Adding the list of known property names currently makes the error tooltip too big and messes up the UI.
      //String message = "Property \"${name.text}\" is not recognized. Known property names are [" + allProperties.join(", ") + "]");
      String message = "Property \"${name.text}\" is not recognized.";
      errorEmitter.emitMessage(name.span, message);
    }
    
    switch(name.text) {
      case "manifest_version":
        return new ManifestVersionValidator(errorEmitter);
      case "app":
        return new ObjectPropertyValidator(errorEmitter, name.text, new AppValidator(errorEmitter));
      default:
        return NullValidator.instance;
    }
  }
}

// Validator for the "manifest_version" element
class ManifestVersionValidator extends NullValidator {
  static final String message = "Manifest version must be the integer value 1 or 2.";
  final ErrorSink errorEmitter;

  ManifestVersionValidator(this.errorEmitter);

  void propertyValue(JsonEntity value) {
    if (value is! NumberEntity) {
      errorEmitter.emitMessage(value.span, message);
      return;
    }
    NumberEntity numEntity = value as NumberEntity;
    if (numEntity.number is! int) {
      errorEmitter.emitMessage(value.span, message);   
      return;
    }
    if (numEntity.number < 1 || numEntity.number > 2) {
      errorEmitter.emitMessage(value.span, message);   
      return;
    }
  }
}

// Validator for the "app" element
class AppValidator extends NullValidator {
  final ErrorSink errorEmitter;

  AppValidator(this.errorEmitter);

  JsonEntityValidator propertyName(StringEntity name) {
    switch(name.text) {
      case "background":
        return new ObjectPropertyValidator(errorEmitter, name.text, new AppBackgroundValidator(errorEmitter));
      case "service_worker":
        return NullValidator.instance;
      default:
        String message = "Property \"${name.text}\" is not recognized.";
        errorEmitter.emitMessage(name.span, message);
        return NullValidator.instance;
    }
  }
}

// Validator for the "app.background" element
class AppBackgroundValidator extends NullValidator {
  final ErrorSink errorEmitter;

  AppBackgroundValidator(this.errorEmitter);

  JsonEntityValidator propertyName(StringEntity name) {
    switch(name.text) {
      case "scripts":
        return new ArrayPropertyValidator(errorEmitter, name.text, new StringArrayValidator(errorEmitter));
      default:
        String message = "Property \"${name.text}\" is not recognized.";
        errorEmitter.emitMessage(name.span, message);
        return NullValidator.instance;
    }
  }
}

// Validate that every element of an array is a string value.
class StringArrayValidator extends NullValidator {
  final ErrorSink errorEmitter;

  StringArrayValidator(this.errorEmitter);
  
  void arrayElement(JsonEntity value) {
    if (value is! StringEntity) {
      errorEmitter.emitMessage(value.span, "String value expected");
    }
  }
}

// Validates a property value is an object, and use [objectValidator] for
// validating the contents of the object.
class ObjectPropertyValidator extends NullValidator {
  final ErrorSink errorEmitter;
  final String name;
  final JsonEntityValidator objectValidator;

  ObjectPropertyValidator(this.errorEmitter, this.name, this.objectValidator);

  // This is called when we are done parsing the whole property value,
  // i.e. just before leaving this validator.
  void propertyValue(JsonEntity entity) {
    if (entity is! ObjectEntity) {
      errorEmitter.emitMessage(entity.span, "Property \"${name}\" is expected to be an object.");
    }
  }
  
  JsonEntityValidator enterObject() {
    return this.objectValidator;
  }
}

// Validates a property value is an array, and use [arrayValidator] for 
// validating the contents (i.e. elements) of the array.
class ArrayPropertyValidator extends NullValidator {
  final ErrorSink errorEmitter;
  final String name;
  final JsonEntityValidator arrayValidator;

  ArrayPropertyValidator(this.errorEmitter, this.name, this.arrayValidator);

  // This is called when we are done parsing the whole property value,
  // i.e. just before leaving this validator.
  void propertyValue(JsonEntity entity) {
    if (entity is! ArrayEntity) {
      errorEmitter.emitMessage(entity.span, "Property \"${name}\" is expected to be an array.");
    }
  }
  
  JsonEntityValidator enterArray() {
    return this.arrayValidator;
  }
}
