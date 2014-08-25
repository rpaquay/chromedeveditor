// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.app.manifest_validator;

import '../json/json_schema_validator.dart';
import '../json/json_validator.dart';

class ErrorIds {
  static final String INVALID_MANIFEST_VERSION = "INVALID_MANIFEST_VERSION";
  static final String OBSOLETE_MANIFEST_VERSION = "OBSOLETE_MANIFEST_VERSION";
  static final String INVALID_PERMISSION = "INVALID_PERMISSION";
}

/**
 * Json validator for "manifest.json" contents.
 */
class AppManifestValidator extends RootObjectSchemaValidator {
  factory AppManifestValidator(ErrorCollector errorCollector)
  {
    var factory = new AppManifestValidatorFactory(errorCollector);
    var core_factory = new CoreSchemaValidatorFactory(factory, errorCollector);
    return new AppManifestValidator._internal(core_factory, errorCollector);
  }

  AppManifestValidator._internal(
      SchemaValidatorFactory factory, ErrorCollector errorCollector)
    : super(factory, errorCollector, AppManifestSchema);
}

class AppManifestValidatorFactory implements SchemaValidatorFactory {
  final ErrorCollector errorCollector;

  AppManifestValidatorFactory(this.errorCollector);

  SchemaValidator createValidator(dynamic schema) {
    if (schema == "manifest_version") {
      return new ManifestVersionValueValidator(errorCollector);
    } else if (schema == "permission") {
      return new PermissionValueValidator(errorCollector);
    }
    return null;
  }

  bool validateSchemaForTesting(dynamic schema) {
    if (schema == "manifest_version" ||
        schema == "permission") {
      return true;
    }
    return false;
  }

  SchemaValidatorFactory get parentFactory => null;
}

class ManifestVersionValueValidator extends IntValueValidator {
  ManifestVersionValueValidator(ErrorCollector errorCollector)
    : super(errorCollector);

  void checkValue(JsonEntity entity, StringEntity propertyName) {
    assert(propertyName != null);

    if (entity is NumberEntity && entity.number is int) {
      if (entity.number == 1) {
        errorCollector.addMessage(
            ErrorIds.OBSOLETE_MANIFEST_VERSION,
            entity.span,
            "Value 1 is obsolete for property \"${propertyName.text}\".");
      } else if (entity.number != 2) {
        errorCollector.addMessage(
            ErrorIds.INVALID_MANIFEST_VERSION,
            entity.span,
            "Value 1 or 2 is expected for property \"${propertyName.text}\".");
      }
      return;
    }

    super.checkValue(entity, propertyName);
  }
}

class PermissionValueValidator extends StringValueValidator {
  PermissionValueValidator(ErrorCollector errorCollector)
    : super(errorCollector);

  void checkValue(JsonEntity entity, StringEntity propertyName) {
    if (entity is StringEntity) {
      switch(entity.text){
        // From https://developer.chrome.com/apps/declare_permissions
        case "alarms":
        case "audio":
        case "audioCapture":
        case "browser":
        case "clipboardRead":
        case "clipboardWrite":
        case "contextMenus":
        case "copresence":
        case "desktopCapture":
        case "diagnostics":
        case "dns":
        case "experimental":
        case "fileBrowserHandler":
        case "fileSystem":
        case "fileSystemProvider":
        case "gcm":
        case "geolocation":
        case "hid":
        case "identity":
        case "idle":
        case "infobars":
        case "location":
        case "mediaGalleries":
        case "nativeMessaging":
        case "notificationProvider":
        case "notifications":
        case "pointerLock":
        case "power":
        case "pushMessaging":
        case "serial":
        case "signedInDevices":
        case "socket":
        case "storage":
        case "syncFileSystem":
        case "system.cpu":
        case "system.display":
        case "system.memory":
        case "system.network":
        case "system.storage":
        case "tts":
        case "unlimitedStorage":
        case "usb":
        case "usbDevices":
        case "videoCapture":
        case "wallpaper":
        case "webview":
          break;
          
        // From https://developer.chrome.com/extensions/declare_permissions
        case "activeTab":
        case "background":
        case "bookmarks":
        case "browsingData":
        case "contentSettings":
        case "cookies":
        case "debugger":
        case "declarativeContent":
        case "declarativeWebRequest":
        case "downloads":
        case "enterprise.platformKeys":
        case "fontSettings":
        case "history":
        case "management":
        case "pageCapture":
        case "privacy":
        case "processes":
        case "proxy":
        case "sessions":
        case "tabCapture":
        case "tabs":
        case "topSites":
        case "ttsEngines":
        case "webNavigation":
        case "webRequest":
        case "webRequestBlocking":
          break;
        default:
          errorCollector.addMessage(
              ErrorIds.INVALID_PERMISSION,
              entity.span,
              "Permission value \"${entity.text}\" is not recognized.");
          break;
      }
      return;
    }

    super.checkValue(entity, propertyName);
  }
  
  JsonValidator enterObject() {
    // Some permissions are expressed as a dictionary.
    return new PermissionObjectValidator(errorCollector);    
  }
}

class PermissionObjectValidator extends NullValidator {
  final ErrorCollector errorCollector;

  PermissionObjectValidator(this.errorCollector);

  JsonValidator propertyName(StringEntity propertyName) {
    switch(propertyName.text)
    {
      case "socket":
        return new SocketPermissionValidator();
      case "usbDevices":
        return new UsbDevicesValidator();
      default:
        errorCollector.addMessage(
             ErrorIds.INVALID_PERMISSION,
             propertyName.span,
             "Permission value \"${propertyName.text}\" is not recognized.");
        return NullValidator.instance;       
    }
  }
}

class SocketPermissionValidator extends NullValidator {
  
}

class UsbDevicesValidator extends NullValidator {
  
}

/**
 * From https://developer.chrome.com/extensions/manifest
 * and https://developer.chrome.com/apps/manifest
 */
Map AppManifestSchema =
{
  "app": {
    "background": {
      "scripts": ["string"],
    },
    "service_worker": "var"
  },
  "author": "var",
  "automation": "var",
  "background": {
    "persistent": "boolean",
    "page": "string",
    "scripts": ["string"]
  },
  "background_page": "string",  // Legacy (manifest v1)
  "bluetooth": {
    "uuids": ["string"],
    "socket": "boolean",
    "low_energy": "boolean"
  },
  "browser_action": {
    "icons": ["string"],
    "id": "string",
    "default_icon": "var",  // Dictionary("string", "string") || "string"
    "default_title": "string",
    "name": "string",
    "popup": "string",
    "default_popup": "string",
  },
  "chrome_settings_overrides": "var",
  "chrome_ui_overrides": "var",
  "chrome_url_overrides": "var",
  "commands": "var",
  "content_pack": "var",
  "content_scripts": "var",
  "content_security_policy": "var",
  "converted_from_user_script": "var",
  "current_locale": "var",
  "default_locale": "var",
  "description": "string",
  "devtools_page": "var",
  "externally_connectable": "var",
  "file_browser_handlers": "var",
  "file_handlers": "var",
  "homepage_url": "var",
  "icons": "var",
  "import": "var",
  "incognito": "var",
  "input_components": "var",
  "key": "string",
  "kiosk_enabled": "var",
  "kiosk_only": "var",
  "manifest_version": "manifest_version",
  "minimum_chrome_version": "var",
  "nacl_modules": "var",
  "name": "string",
  "oauth2": "var",
  "offline_enabled": "var",
  "omnibox": "var",
  "optional_permissions": ["permission"],
  "options_page": "var",
  "page_action": "var",
  "page_actions": "var",
  "permissions": ["permission"],
  "platforms": "var",
  "plugins": "var",
  "requirements": "var",
  "sandbox": "var",
  "script_badge": "var",
  "short_name": "string",
  "signature": "var",
  "sockets": {
    "udp": {
      "bind": "var",
      "send": "var",
      "multicastMembership": "var"
    },
    "tcp": {
      "connect": "var"
    },
    "tcpServer": {
      "listen": "var"
    }
  },
  "spellcheck": "var",
  "storage": "var",
  "system_indicator": "var",
  "tts_engine": "var",
  "update_url": "string",
  "web_accessible_resources": "var",
  "url_handlers": "var",
  "version": "var",
  "webview": "var",
};
