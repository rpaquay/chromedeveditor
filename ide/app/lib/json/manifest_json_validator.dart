// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.manifest_json_validator;

import 'json_validator.dart';

// Initial validator for manifest.json contents.
class RootValidator extends NullValidator {
  final ErrorSink errorSink;

  RootValidator(this.errorSink);

  JsonEntityValidator enterObject() {
    return new TopLevelValidator(errorSink);
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

  final ErrorSink errorSink;

  TopLevelValidator(this.errorSink);

  JsonEntityValidator propertyName(StringEntity name) {
    if (!allProperties.contains(name.text)) {
      // TODO(rpaquay): Adding the list of known property names currently makes the error tooltip too big and messes up the UI.
      //String message = "Property \"${name.text}\" is not recognized. Known property names are [" + allProperties.join(", ") + "]");
      String message = "Property \"${name.text}\" is not recognized.";
      errorSink.emitMessage(name.span, message);
    }
    
    switch(name.text) {
      case "manifest_version":
        return new ManifestVersionValidator(errorSink);
      case "app":
        return new ObjectPropertyValidator(errorSink, name.text, new AppValidator(errorSink));
      default:
        return NullValidator.instance;
    }
  }
}

// Validator for the "manifest_version" element
class ManifestVersionValidator extends NullValidator {
  static final String message = "Manifest version must be the integer value 1 or 2.";
  final ErrorSink errorSink;

  ManifestVersionValidator(this.errorSink);

  void propertyValue(JsonEntity value) {
    if (value is! NumberEntity) {
      errorSink.emitMessage(value.span, message);
      return;
    }
    NumberEntity numEntity = value as NumberEntity;
    if (numEntity.number is! int) {
      errorSink.emitMessage(value.span, message);   
      return;
    }
    if (numEntity.number < 1 || numEntity.number > 2) {
      errorSink.emitMessage(value.span, message);   
      return;
    }
  }
}

// Validator for the "app" element
class AppValidator extends NullValidator {
  final ErrorSink errorSink;

  AppValidator(this.errorSink);

  JsonEntityValidator propertyName(StringEntity name) {
    switch(name.text) {
      case "background":
        return new ObjectPropertyValidator(errorSink, name.text, new AppBackgroundValidator(errorSink));
      case "service_worker":
        return NullValidator.instance;
      default:
        String message = "Property \"${name.text}\" is not recognized.";
        errorSink.emitMessage(name.span, message);
        return NullValidator.instance;
    }
  }
}

// Validator for the "app.background" element
class AppBackgroundValidator extends NullValidator {
  final ErrorSink errorSink;

  AppBackgroundValidator(this.errorSink);

  JsonEntityValidator propertyName(StringEntity name) {
    switch(name.text) {
      case "scripts":
        return new ArrayPropertyValidator(errorSink, name.text, new StringArrayValidator(errorSink));
      default:
        String message = "Property \"${name.text}\" is not recognized.";
        errorSink.emitMessage(name.span, message);
        return NullValidator.instance;
    }
  }
}

// Validate that every element of an array is a string value.
class StringArrayValidator extends NullValidator {
  final ErrorSink errorSink;

  StringArrayValidator(this.errorSink);
  
  void arrayElement(JsonEntity value) {
    if (value is! StringEntity) {
      errorSink.emitMessage(value.span, "String value expected");
    }
  }
}

// Validates a property value is an object, and use [objectValidator] for
// validating the contents of the object.
class ObjectPropertyValidator extends NullValidator {
  final ErrorSink errorSink;
  final String name;
  final JsonEntityValidator objectValidator;

  ObjectPropertyValidator(this.errorSink, this.name, this.objectValidator);

  // This is called when we are done parsing the whole property value,
  // i.e. just before leaving this validator.
  void propertyValue(JsonEntity entity) {
    if (entity is! ObjectEntity) {
      errorSink.emitMessage(entity.span, "Property \"${name}\" is expected to be an object.");
    }
  }
  
  JsonEntityValidator enterObject() {
    return this.objectValidator;
  }
}

// Validates a property value is an array, and use [arrayValidator] for 
// validating the contents (i.e. elements) of the array.
class ArrayPropertyValidator extends NullValidator {
  final ErrorSink errorSink;
  final String name;
  final JsonEntityValidator arrayValidator;

  ArrayPropertyValidator(this.errorSink, this.name, this.arrayValidator);

  // This is called when we are done parsing the whole property value,
  // i.e. just before leaving this validator.
  void propertyValue(JsonEntity entity) {
    if (entity is! ArrayEntity) {
      errorSink.emitMessage(entity.span, "Property \"${name}\" is expected to be an array.");
    }
  }
  
  JsonEntityValidator enterArray() {
    return this.arrayValidator;
  }
}
