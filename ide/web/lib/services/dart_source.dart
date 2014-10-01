// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_source;

import "dart:async";

import 'package:analyzer_clone/src/generated/engine.dart';
import 'package:analyzer_clone/src/generated/source.dart';

import 'services_utils.dart' as utils;

abstract class ContentsProvider {
  Future<String> getFileContents(String uuid);
  Future<String> getPackageContents(String relativeUuid, String packageRef);
}

/**
 * An implementation of [Source] based on an in-memory Dart string.
 */
class StringSource extends Source {
  final String _contents;
  final String fullName;
  final int modificationStamp;

  StringSource(this._contents, this.fullName)
      : modificationStamp = new DateTime.now().millisecondsSinceEpoch;

  @override
  bool operator==(Object object) {
    if (object is StringSource) {
      return object._contents == _contents && object.fullName == fullName;
    } else {
      return false;
    }
  }

  @override
  bool exists() => true;

  @override
  TimestampedData<String> get contents =>
      new TimestampedData<String>(modificationStamp, _contents);

  void getContentsToReceiver(Source_ContentReceiver receiver) =>
      receiver.accept(_contents, modificationStamp);

  @override
  String get encoding => 'UTF-8';

  @override
  String get shortName => fullName;

  @override
  UriKind get uriKind =>
      throw new UnsupportedError("StringSource doesn't support uriKind.");

  @override
  Uri get uri => new Uri(path: fullName);

  @override
  int get hashCode => _contents.hashCode ^ fullName.hashCode;

  @override
  bool get isInSystemLibrary => false;

  @override
  Uri resolveRelativeUri(Uri relativeUri) =>
      resolveRelativeUriHelper(uri, relativeUri);
}

/**
 * A [Source] abstract base class based on workspace uuids.
 */
abstract class WorkspaceSource extends Source {
  static final FILE_SCHEME = "file";
  static final PACKAGE_SCHEME = "package";
  String uuid;

  int modificationStamp;
  bool _exists = true;
  String _strContents;

  /**
   * Creates an concrete instance of [WorkspaceSource] according to the format
   * of [uuid].
   * For source files in packages, [uuid] follows a
   * "package:package_name/source_path" format.
   * For source files part of the application, [uuid] follows
   * a "chrome-app-id:app-name/source_path" format.
   */
  factory WorkspaceSource(String uuid) {
    assert(uuid != null);
    if (uuid.startsWith(PACKAGE_SCHEME + ":")) {
      return new PackageSource(uuid);
    } else {
      return new FileSource(uuid);
    }
  }

  WorkspaceSource._(this.uuid) {
    touchFile();
  }

  @override
  bool operator==(Object object) {
    return object is WorkspaceSource ? object.uuid == uuid : false;
  }

  @override
  bool exists() => _exists;

  String get rawContents => _strContents;

  @override
  TimestampedData<String> get contents =>
    new TimestampedData(modificationStamp, _strContents);

  void getContentsToReceiver(Source_ContentReceiver receiver) {
    TimestampedData cnts = contents;
    receiver.accept(cnts.data, cnts.modificationTime);
  }

  @override
  String get encoding => 'UTF-8';

  @override
  String get shortName => utils.basename(uuid);

  @override
  Uri get uri => new Uri(scheme: getScheme(), path: fullName);

  @override
  int get hashCode => uuid.hashCode;

  @override
  bool get isInSystemLibrary => false;

  @override
  Uri resolveRelativeUri(Uri relativeUri) =>
    resolveRelativeUriHelper(uri, relativeUri);

  void setContents(String newContents, bool exists) {
    _strContents = newContents;
    _exists = exists;
    touchFile();
  }

  void touchFile() {
    modificationStamp = new DateTime.now().millisecondsSinceEpoch;
  }

  @override
  String toString() => uuid;

  String getScheme();

  @override
  String get fullName;

  @override
  UriKind get uriKind;
}

/**
 * A source file from a package.
 */
class PackageSource extends WorkspaceSource {
  PackageSource(String uuid): super._(uuid);

  @override
  String getScheme() => WorkspaceSource.PACKAGE_SCHEME;

  @override
  String get fullName {
    int index = uuid.indexOf(":");
    return index == -1 ? uuid : uuid.substring(index + 1);
  }

  @override
  UriKind get uriKind => UriKind.PACKAGE_URI;
}

/**
 * A regular source file from the application.
 */
class FileSource extends WorkspaceSource {
  FileSource(String uuid): super._(uuid);

  @override
  String getScheme() => WorkspaceSource.FILE_SCHEME;

  @override
  String get fullName {
    int index = uuid.indexOf('/');
    return index == -1 ? uuid : uuid.substring(index + 1);
  }

  @override
  UriKind get uriKind => UriKind.FILE_URI;
}

class DartAnalyzerHelpers {
  /**
   * Populate the contents for the [WorkspaceSource]s.
   */
  static Future populateSources(
      String relativeUuid,
      Map<String, WorkspaceSource> sources,
      ContentsProvider contentsProvider) {
    List<Future> futures = [];

    sources.forEach((String uuid, WorkspaceSource source) {
      if (source.exists() && source.rawContents == null) {
        Future f;

        if (FileUuidHelpers.isPackageFile(uuid)) {
          f = contentsProvider.getPackageContents(relativeUuid, uuid).then((String str) {
            source.setContents(str, true);
          });
        } else {
          f = contentsProvider.getFileContents(uuid).then((String str) {
            source.setContents(str, true);
          });
        }

        futures.add(f);
      }
    });

    return Future.wait(futures);
  }

  static void processChanges(
     List<String> addedUuids,
     List<String> changedUuids,
     List<String> deletedUuids,
     ChangeSet changeSet,
     Map<String, WorkspaceSource> _sources) {

    // added
    for (String uuid in addedUuids) {
      _sources[uuid] = new WorkspaceSource(uuid);
      if (FileUuidHelpers.isDartSource(uuid)) {
        changeSet.addedSource(_sources[uuid]);
      }
    }

    // changed
    for (String uuid in changedUuids) {
      if (_sources[uuid] != null) {
        if (FileUuidHelpers.isDartSource(uuid)) {
          changeSet.changedSource(_sources[uuid]);
        }
        _sources[uuid].setContents(null, true);
      } else {
        _sources[uuid] = new WorkspaceSource(uuid);
        if (FileUuidHelpers.isDartSource(uuid)) {
          changeSet.addedSource(_sources[uuid]);
        }
      }
    }

    // deleted
    for (String uuid in deletedUuids) {
      if (_sources[uuid] != null) {
        // TODO(devoncarew): Should we set this to deleted or remove the FileSource?
        _sources[uuid].setContents(null, false);
        Source source = _sources.remove(uuid);
        if (FileUuidHelpers.isDartSource(uuid)) {
          changeSet.removedSource(source);
        }
      }
    }
  }
}

/**
 * Note: this code is mostly a copy-paste of
 * `FileBasedSource.resolveRelativeUri` in the
 * `package:analyzer/source_io.dart` file. We cannot re-use the
 * implementation because we cannot use `dart:io`.
 */
Uri resolveRelativeUriHelper(Uri uri, Uri containedUri) {
  Uri baseUri = uri;
  bool isOpaque = uri.isAbsolute && !uri.path.startsWith('/');
  if (isOpaque) {
    String scheme = uri.scheme;
    String part = uri.path;
    if (scheme == DartUriResolver.DART_SCHEME && part.indexOf('/') < 0) {
      part = "${part}/${part}.dart";
    }
    baseUri = utils.parseUriWithException("${scheme}:/${part}");
  }
  Uri result = baseUri.resolveUri(containedUri);
  if (isOpaque) {
    result = utils.parseUriWithException("${result.scheme}:${result.path.substring(1)}");
  }
  return result;
}

class FileUuidHelpers {
  /// Returns `true` if [uuid] is a package file uuid.
  static bool isPackageFile(String uuid) {
    return uuid.indexOf("package:") == 0;
  }

  /// Returns `true` if [uuid] is a library file uuid.
  static bool isLibraryFile(String uuid) {
    return uuid.indexOf("dart:") == 0;
  }

  /// Returns `true` if [uuid] is a application source file uuid.
  static bool isAppFile(String uuid) {
    assert(uuid.indexOf(":") >= 0);
    return !isPackageFile(uuid) && !isLibraryFile(uuid);
  }

  static bool isDartSource(String uuid) {
    return uuid.endsWith('.dart');
  }

  /// Returns `true` if [id] is a project context id.
  static bool isProjectId(String projectId) {
    return isAppFile(projectId) && projectId.indexOf("/") < 0;
  }

  /// Returns the project path part of a project id.
  static String getProjectIdProjectPath(String projectId) {
    assert(isProjectId(projectId));

    int colon = projectId.indexOf(":");
    assert(colon >= 0);
    return projectId.substring(colon + 1);
  }

  /// Returns the project id part of an application source file uuid.
  static String getAppFileProjectId(String uuid) {
    assert(isAppFile(uuid));

    int separator = uuid.indexOf("/");
    if (separator >= 0) {
      return uuid.substring(0, separator);
    }
    return uuid;
  }

  /// Returns the project root path of an application source file uuid.
  static String getAppFileProjectPath(String uuid) {
    assert(isAppFile(uuid));

    return getProjectIdProjectPath(getAppFileProjectId(uuid));
  }

  /// Returns the path relative to the project root path for the given
  /// application source file uuid.
  static String getAppFileRelativePath(String uuid) {
    assert(isAppFile(uuid));

    int separator = uuid.indexOf("/");
    if (separator >= 0) {
      return uuid.substring(separator + 1);
    }
    return "";
  }

  /// Returns the package name of a package source file uuid.
  static String getPackageName(String uuid) {
    assert(isPackageFile(uuid));

    int colon = uuid.indexOf(":");
    assert(colon >= 0);
    int separator = uuid.indexOf("/");
    if (separator >= 0) {
      assert(separator > colon);
      return uuid.substring(colon + 1, separator);
    }
    return uuid.substring(colon + 1);
  }

  /// Returns the file name of a package source file uuid.
  static String getPackageFilePath(String uuid) {
    assert(isPackageFile(uuid));

    int separator = uuid.indexOf("/");
    if (separator >= 0) {
      return uuid.substring(separator + 1);
    }
    return "";
  }

  /// Returns the file uuid from a project id and a file relative path.
  static String buildAppFileUuid(String projectId, String relativePath) {
    assert(projectId != null);
    assert(projectId.isNotEmpty);
    assert(relativePath != null);
    assert(relativePath.isNotEmpty);
    return utils.pathconcat(projectId,  relativePath);
  }

  /// Returns the full path of a file name from a project id and a relative path.
  static String buildAppFileFullPath(String projectId, String relativePath) {
    assert(projectId != null);
    assert(projectId.isNotEmpty);
    assert(relativePath != null);
    assert(relativePath.isNotEmpty);
    return utils.pathconcat(getProjectIdProjectPath(projectId), relativePath);
  }
}
