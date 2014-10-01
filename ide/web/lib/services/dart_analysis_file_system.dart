// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_fie_system;

import 'dart:async';

import 'package:analyzer_clone/file_system/file_system.dart';
import 'package:analyzer_clone/src/generated/source.dart';
import 'package:path/src/context.dart';
import 'package:watcher/src/watch_event.dart';

import 'dart_analysis_logger.dart';
import 'dart_source.dart';
import 'services_utils.dart' as utils;

/**
 * Abstraction over the list of files included in a project.
 * This includes Dart package source files, Dart application source files and
 * other meaningful (e.g. "pubspec.yaml") files.
 */
abstract class ProjectFiles {
  /** Returns the unique project identifier */
  String get projectId;

  /** Returns the unique root path of the project */
  String get rootPath;

  /** Returns the list of all files included in the project */
  Iterable<WorkspaceSource> get allFiles;

  /** Returns the list of Dart source files included  in the project */
  Iterable<WorkspaceSource> get dartSourceFiles =>
      allFiles.where((WorkspaceSource source) =>
          FileUuidHelpers.isAppFile(source.uuid) &&
          FileUuidHelpers.isDartSource(source.uuid));

  /** Returns the list of other files included  in the project */
  Iterable<WorkspaceSource> get otherFiles =>
      allFiles.where((WorkspaceSource source) =>
          FileUuidHelpers.isAppFile(source.uuid) &&
          !FileUuidHelpers.isDartSource(source.uuid));

  /** Returns the list of other files included  in the project */
  Iterable<WorkspaceSource> get packageSourceFiles =>
      allFiles.where((WorkspaceSource source) =>
          FileUuidHelpers.isPackageFile(source.uuid) &&
          FileUuidHelpers.isDartSource(source.uuid));

  /** Returns the list of files of the project (dart source or not) */
  Iterable<WorkspaceSource> get projectFiles =>
      allFiles.where((WorkspaceSource source) =>
          !FileUuidHelpers.isPackageFile(source.uuid));
}

/**
 * Instances of the class [ResourceProvider] convert [String] paths into
 * [Resource]s.
 */
class LocalResourceProvider implements ResourceProvider {
  /** Map from project root path to [ProjectRootFolder] instances */
  final Map<String, ProjectRootFolder> _projectFolders = {};

  /**
   * Get the path context used by this resource provider.
   */
  @override
  final Context pathContext = new Context();

  /**
   * Adds a new project and returns a new corresponding [ProjectRootFolder] instance.
   */
  ProjectRootFolder addFolder(ProjectFiles state) {
    assert(_projectFolders[state.rootPath] == null);
    ProjectFileSystem fileSystem = new ProjectFileSystem(state);
    ProjectRootFolder result = new ProjectRootFolder(fileSystem);
    assert(result.path == state.rootPath);
    _projectFolders[result.path] = result;
    return result;
  }

  void removeProject(ProjectRootFolder folder) {
    assert(_projectFolders[folder.path] != null);
    _projectFolders.remove(folder.path);
  }

  /**
   * Return the [Resource] that corresponds to the given [path].
   */
  @override
  Resource getResource(String path) {
    AnalysisLogger.instance.debug("LocalResourceProvider.getResource(\"${path}\")");

    ResourcePath resourcePath = splitPath(path);
    if (resourcePath == null) {
      return null;
    }
    ProjectRootFolder folder = _projectFolders[resourcePath.folderPath];
    if (folder == null) {
      return null;
    }
    if (resourcePath.resourcePath.isEmpty) {
      return folder;
    }
    return folder.getChild(resourcePath.resourcePath);
  }

  ResourcePath splitPath(String path) {
    String projectRootPath = _projectFolders.keys
      .firstWhere((String folderPath) => path == folderPath, orElse: () => null);
    if (projectRootPath == null) {
      return null;
    }

    assert(projectRootPath.length > 0);
    assert(projectRootPath[projectRootPath.length - 1] != '/');
    String relativePath = path.substring(projectRootPath.length);
    if (relativePath.length > 0) {
      if (relativePath[0] == "/") {
        relativePath = relativePath.substring(1);
      }
    }
    return new ResourcePath(projectRootPath, relativePath);
  }
}

class ResourcePath {
  final String folderPath;
  final String resourcePath;

  ResourcePath(this.folderPath, this.resourcePath);
}

/**
 * [Folder] implementation of the root folder of a project.
 */
class ProjectRootFolder extends ProjectFolderBase {
  ProjectRootFolder(ProjectFileSystem fileSystem)
    : super(fileSystem, "");

  Iterable<WorkspaceSource> get packageSourceFiles =>
      _projectFileSystem._projectState.packageSourceFiles;
}

/**
 * Abstraction over the file system of a project.
 */
class ProjectFileSystem {
  final ProjectFiles _projectState;

  ProjectFileSystem(this._projectState);

  Resource getChildResource(String relativePath) {
    AnalysisLogger.instance.debug("ProjectContextRootFolder.getChild(${relativePath})");

    Source source = _projectState.projectFiles
        .firstWhere((WorkspaceSource source) => FileUuidHelpers.getAppFileRelativePath(source.uuid) == relativePath,
        orElse: () => null);
    if (source != null) {
      return new ProjectFile(this, relativePath, source);
    }

    // TODO(rpaquay): Support folder?
    Source folderPath = _projectState.projectFiles
        .firstWhere((WorkspaceSource source) {
          String sourcePath = FileUuidHelpers.getAppFileRelativePath(source.uuid);
          if (sourcePath.isEmpty) return false;
          String folderPath = utils.dirname(relativePath);
          return (folderPath == relativePath);
        },
        orElse: () => null);
    if (source != null) {
      return new ProjectFolder(this, relativePath);
    }
    return new NonExistentFile(this, relativePath);
  }

  List<Resource> getChildResources(String relativePath) {
    AnalysisLogger.instance.debug("ProjectContextRootFolder.getChildResource(\"${relativePath}\")");

    // Go through all project files, keeping only files directly inside
    // [relativePath], but also creating [Folder] instances for files that
    // are inside a folder inside [relativePath].
    Map<String, Resource> result = {};
    _projectState.projectFiles.forEach((WorkspaceSource source) {
      String sourceRelativePath = FileUuidHelpers.getAppFileRelativePath(source.uuid);
      String sourceFolderPath = utils.dirname(sourceRelativePath);

      // Simple case: a source file inside the [relativePath]
      if (sourceFolderPath == relativePath) {
        result[sourceRelativePath] = new ProjectFile(this, sourceRelativePath, source);
      } else if (sourceFolderPath.indexOf(relativePath) == 0) {
        String currentPath = sourceRelativePath;
        String parentPath = utils.dirname(currentPath);
        while (parentPath != relativePath) {
          currentPath = parentPath;
          parentPath = utils.dirname(parentPath);
        }
        result[currentPath] = new ProjectFolder(this, currentPath);
      }
    });

    return result.values.toList();
  }

  Stream<WatchEvent> getFolderChanges(ProjectFolderBase folder) =>
    // TODO(rpaquay): Keep track of instances and actually use them.
    new StreamController<WatchEvent>.broadcast().stream;

  /**
   * If the path [path] is a relative path, convert it to an absolute path
   * by interpreting it relative to this folder.  If it is already an aboslute
   * path, then don't change it.
   *
   * However, regardless of whether [path] is relative or absolute, normalize
   * it by removing path components of the form '.' or '..'.
   */
  String canonicalizePath(ProjectFolderBase folder, String path) =>
      // TODO(rpaquay): Fix this!
      utils.pathconcat(folder.path,  path);

  Folder getParentFolder(ProjectResourceBase resource) {
    String relativePath = resource.relativePath;
    if (relativePath.isEmpty) {
      return null;
    }
    String parentPath = utils.dirname(relativePath);
    if (parentPath.isEmpty) {
      return new ProjectRootFolder(this);
    }

    return new ProjectFolder(this, parentPath);
  }
}

abstract class ProjectResourceBase implements Resource {
  /** The file system this [Resoure] lives in. */
  final ProjectFileSystem _projectFileSystem;
  /** The path relative from the project root path */
  final String relativePath;

  ProjectResourceBase(this._projectFileSystem, this.relativePath);

  /**
   * Return `true` if this resource exists.
   */
  @override
  bool get exists => true;

  /**
   * Return the [Folder] that contains this resource, or `null` if this resource
   * is a root folder.
   */
  @override
  Folder get parent => _projectFileSystem.getParentFolder(this);

  /**
   * Return the full path to this resource.
   */
  @override
  String get path => utils.pathconcat(_projectFileSystem._projectState.rootPath, relativePath);

  /**
   * Return a short version of the name that can be displayed to the user to
   * denote this resource.
   */
  @override
  String get shortName => utils.basename(path);

  /**
   * Return `true` if absolute [path] references this resource or a resource in
   * this folder.
   */
  @override
  bool isOrContains(String path) => this.path.indexOf(path) == 0;

  @override
  int get hashCode =>
      // TODO(rpaquay): Include project id?
      path.hashCode;

  @override
  bool operator==(other) =>
      // TODO(rpaquay): Include project id?
      other is ProjectResourceBase && this.path == other.path;
}

/**
 * Base class for project folder implementations.
 */
abstract class ProjectFolderBase extends ProjectResourceBase implements Folder {
  ProjectFolderBase(ProjectFileSystem projectFileSystem, String relativePath)
    : super(projectFileSystem, relativePath);

  /**
   * Watch for changes to the files inside this folder (and in any nested
   * folders, including folders reachable via links).
   */
  @override
  Stream<WatchEvent> get changes =>
      _projectFileSystem.getFolderChanges(this);

  /**
   * If the path [path] is a relative path, convert it to an absolute path
   * by interpreting it relative to this folder.  If it is already an aboslute
   * path, then don't change it.
   *
   * However, regardless of whether [path] is relative or absolute, normalize
   * it by removing path components of the form '.' or '..'.
   */
  @override
  String canonicalizePath(String path) =>
      _projectFileSystem.canonicalizePath(this, path);

  /**
   * Return `true` if absolute [path] references a resource in this folder.
   */
  @override
  bool contains(String path) => this.path.indexOf(path) == 0;

  /**
   * Return an existing child [Resource] with the given [relPath].
   * Return a not existing [File] if no such child exist.
   */
  @override
  Resource getChild(String relPath) =>
      _projectFileSystem.getChildResource(utils.pathconcat(this.relativePath, relPath));

  /**
   * Return a list of existing direct children [Resource]s (folders and files)
   * in this folder, in no particular order.
   */
  @override
  List<Resource> getChildren() =>
      _projectFileSystem.getChildResources(this.relativePath);
}

/**
 * Base class for project file implementations.
 */
abstract class ProjectFileBase extends ProjectResourceBase implements File {
  ProjectFileBase(ProjectFileSystem projectFileSystem, String relativePath)
    : super(projectFileSystem, relativePath);

  /**
   * Create a new [Source] instance that serves this file.
   */
  Source createSource([Uri uri]) {
    AnalysisLogger.instance.debug("ProjectFileBase(\"${path}\").getSource()");
    return source;
  }

  WorkspaceSource get source;
}

/**
 * A [Folder] inside a package inside a project.
 */
class ProjectFolder extends ProjectFolderBase {
  ProjectFolder(ProjectFileSystem projectFileSystem, String relativePath)
    : super(projectFileSystem, relativePath);
}

/**
 * A [File] implementation of a source file in a project.
 */
class ProjectFile extends ProjectFileBase {
  @override
  final Source source;

  ProjectFile(ProjectFileSystem fileSystem, String relativePath, this.source)
    : super(fileSystem, relativePath);

}

/**
 * [File] implementation of a project file that does not exist on disk.
 */
class NonExistentFile extends ProjectFileBase {
  NonExistentFile(ProjectFileSystem fileSystem, String relativePath)
    : super(fileSystem, relativePath);

  @override
  bool get exists => false;

  @override
  Source get source => null;
}
