// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_analysis_file_system;

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
    ProjectFileSystem fileSystem = new ProjectFileSystemImpl(state);
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
    int separatorIndex = path.indexOf("/");
    String folderPath = (separatorIndex < 0 ? path : path.substring(0, separatorIndex));
    String projectRootPath = _projectFolders.keys
      .firstWhere((String x) => x == folderPath, orElse: () => null);
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

  PackageRootFolder getPackageRootFolder() {
    return new PackageRootFolder(new PackageFileSystemImpl(_fileSystem.packageSources));
  }
}

abstract class ProjectFileSystem {
  String get rootPath;
  Iterable<WorkspaceSource> get sources;
  Iterable<WorkspaceSource> get packageSources;
  Folder getParentFolder(ProjectResourceBase resource);
  Resource getChildResource(String relativePath);
  List<Resource> getChildResources(String relativePath);
  Stream<WatchEvent> getFolderChanges(ProjectFolderBase folder);
  String canonicalizePath(ProjectFolderBase folder, String path);
}

/**
 * Abstraction over the file system of a project.
 */
class ProjectFileSystemImpl implements ProjectFileSystem {
  final ProjectFiles _projectFiles;

  ProjectFileSystemImpl(this._projectFiles);

  @override
  String get rootPath => _projectFiles.rootPath;

  @override
  Iterable<WorkspaceSource> get sources => _projectFiles.projectFiles;

  @override
  Iterable<WorkspaceSource> get packageSources => _projectFiles.packageSourceFiles;

  @override
  Resource getChildResource(String relativePath) {
    AnalysisLogger.instance.debug("ProjectFileSystem.getChild(\"${relativePath}\")");
    if (relativePath.isEmpty) {
      return new ProjectRootFolder(this);
    }

    Source source = _projectFiles.projectFiles
        .firstWhere((WorkspaceSource source) => FileUuidHelpers.getAppFileRelativePath(source.uuid) == relativePath,
        orElse: () => null);
    if (source != null) {
      return new ProjectFile(this, relativePath, source);
    }

    Source folderPath = _projectFiles.projectFiles
        .firstWhere((WorkspaceSource source) {
          String sourcePath = FileUuidHelpers.getAppFileRelativePath(source.uuid);
          if (sourcePath.isEmpty) return false;
          String folderPath = utils.dirname(relativePath);
          return (folderPath == relativePath);
        },
        orElse: () => null);
    if (folderPath != null) {
      return new ProjectFolder(this, relativePath);
    }
    return new NonExistentFile(this, relativePath);
  }

  @override
  List<Resource> getChildResources(String relativePath) {
    AnalysisLogger.instance.debug("ProjectFileSystem.getChildResource(\"${relativePath}\")");

    // Go through all project files, keeping only files directly inside
    // [relativePath], but also creating [Folder] instances for files that
    // are inside a folder inside [relativePath].
    Map<String, Resource> result = {};
    _projectFiles.projectFiles.forEach((WorkspaceSource source) {
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

  @override
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
  @override
  String canonicalizePath(ProjectFolderBase folder, String path) =>
      // TODO(rpaquay): Fix this!
      utils.pathconcat(folder.path,  path);

  @override
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
  final ProjectFileSystem _fileSystem;
  /** The path relative from the project root path */
  final String relativePath;

  ProjectResourceBase(this._fileSystem, this.relativePath);

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
  Folder get parent => _fileSystem.getParentFolder(this);

  /**
   * Return the full path to this resource.
   */
  @override
  String get path => utils.pathconcat(_fileSystem.rootPath, relativePath);

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
  ProjectFolderBase(ProjectFileSystem fileSystem, String relativePath)
    : super(fileSystem, relativePath);

  /**
   * Watch for changes to the files inside this folder (and in any nested
   * folders, including folders reachable via links).
   */
  @override
  Stream<WatchEvent> get changes =>
      _fileSystem.getFolderChanges(this);

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
      _fileSystem.canonicalizePath(this, path);

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
      _fileSystem.getChildResource(utils.pathconcat(this.relativePath, relPath));

  /**
   * Return a list of existing direct children [Resource]s (folders and files)
   * in this folder, in no particular order.
   */
  @override
  List<Resource> getChildren() =>
      _fileSystem.getChildResources(this.relativePath);
}

/**
 * Base class for project file implementations.
 */
abstract class ProjectFileBase extends ProjectResourceBase implements File {
  ProjectFileBase(ProjectFileSystem fileSystem, String relativePath)
    : super(fileSystem, relativePath);

  /**
   * Create a new [Source] instance that serves this file.
   */
  Source createSource([Uri uri]) {
    AnalysisLogger.instance.debug("ProjectFileBase(\"${path}\").createSource(${uri == null ? "<null>" : uri})");
    return source;
  }

  WorkspaceSource get source;
}

/**
 * A [Folder] inside a package inside a project.
 */
class ProjectFolder extends ProjectFolderBase {
  ProjectFolder(ProjectFileSystem fileSystem, String relativePath)
    : super(fileSystem, relativePath);
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

abstract class PackageFileSystem {
  String get rootPath;
  Iterable<WorkspaceSource> get sources;
  Folder getParentFolder(PackageResourceBase resource);
  Resource getChildResource(String relativePath);
  List<Resource> getChildResources(String relativePath);
  Stream<WatchEvent> getFolderChanges(PackageFolderBase folder);
  String canonicalizePath(PackageFolderBase folder, String path);
}

class PackageFileSystemImpl implements PackageFileSystem {
  final Iterable<WorkspaceSource> _packageSources;

  PackageFileSystemImpl(this._packageSources);

  @override
  String get rootPath => "packages";

  @override
  Iterable<WorkspaceSource> get sources => _packageSources;

  @override
  Resource getChildResource(String relativePath) {
    AnalysisLogger.instance.debug("PackageFileSystemImpl.getChild(\"${relativePath}\")");
    if (relativePath.isEmpty) {
      return new PackageRootFolder(this);
    }

    Source source = _packageSources
        .firstWhere((WorkspaceSource source) =>
            FileUuidHelpers.getPackageFileRelativePath(source.uuid) == relativePath,
        orElse: () => null);
    if (source != null) {
      return new PackageFile(this, relativePath, source);
    }

    Source folderPath = _packageSources
        .firstWhere((WorkspaceSource source) {
          // TODO(rpaquay): Does this work when there are empty folder int the path?
          String sourcePath = FileUuidHelpers.getPackageFileRelativePath(source.uuid);
          if (sourcePath.isEmpty) return false;
          String folderPath = utils.dirname(relativePath);
          return (folderPath == relativePath);
        },
        orElse: () => null);
    if (folderPath != null) {
      return new PackageFolder(this, relativePath);
    }
    return new NonExistentPackageFile(this, relativePath);
  }


  @override
  List<Resource> getChildResources(String relativePath) {
    AnalysisLogger.instance.debug("PackageFileSystemImpl.getChildResource(\"${relativePath}\")");

    // Go through all project files, keeping only files directly inside
    // [relativePath], but also creating [Folder] instances for files that
    // are inside a folder inside [relativePath].
    Map<String, Resource> result = {};
    _packageSources.forEach((WorkspaceSource source) {
      String sourceRelativePath = FileUuidHelpers.getPackageFileRelativePath(source.uuid);
      String sourceFolderPath = utils.dirname(sourceRelativePath);

      // Simple case: a source file inside the [relativePath]
      if (sourceFolderPath == relativePath) {
        result[sourceRelativePath] = new PackageFile(this, sourceRelativePath, source);
      } else if (sourceFolderPath.indexOf(relativePath) == 0) {
        String currentPath = sourceRelativePath;
        String parentPath = utils.dirname(currentPath);
        while (parentPath != relativePath) {
          currentPath = parentPath;
          parentPath = utils.dirname(parentPath);
        }
        result[currentPath] = new PackageFolder(this, currentPath);
      }
    });

    return result.values.toList();
  }

  @override
  Stream<WatchEvent> getFolderChanges(PackageFolderBase folder) =>
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
  @override
  String canonicalizePath(PackageFolderBase folder, String path) =>
      // TODO(rpaquay): Fix this!
      utils.pathconcat(folder.path,  path);

  @override
  Folder getParentFolder(PackageResourceBase resource) {
    String relativePath = resource.relativePath;
    if (relativePath.isEmpty) {
      return null;
    }
    String parentPath = utils.dirname(relativePath);
    if (parentPath.isEmpty) {
      return new PackageRootFolder(this);
    }

    return new PackageFolder(this, parentPath);
  }
}

/**
 * Base class for all [File] and [Folder] inside a package inside a project.
 */
abstract class PackageResourceBase implements Resource {
  /** The file system this [Resoure] lives in. */
  final PackageFileSystem _fileSystem;
  /** The path relative from the package root */
  final String relativePath;

  PackageResourceBase(this._fileSystem, this.relativePath);

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
  Folder get parent => _fileSystem.getParentFolder(this);

  /**
   * Return the full path to this resource.
   */
  @override
  String get path => utils.pathconcat(_fileSystem.rootPath, relativePath);

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
      other is PackageResourceBase && this.path == other.path;
}

/**
 * Base class for project folder implementations.
 */
abstract class PackageFolderBase extends PackageResourceBase implements Folder {
  PackageFolderBase(PackageFileSystem fileSystem, String relativePath)
    : super(fileSystem, relativePath);

  /**
   * Watch for changes to the files inside this folder (and in any nested
   * folders, including folders reachable via links).
   */
  @override
  Stream<WatchEvent> get changes =>
      _fileSystem.getFolderChanges(this);

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
      _fileSystem.canonicalizePath(this, path);

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
      _fileSystem.getChildResource(utils.pathconcat(this.relativePath, relPath));

  /**
   * Return a list of existing direct children [Resource]s (folders and files)
   * in this folder, in no particular order.
   */
  @override
  List<Resource> getChildren() =>
      _fileSystem.getChildResources(this.relativePath);
}

/**
 * Base class for project file implementations.
 */
abstract class PackageFileBase extends PackageResourceBase implements File {
  PackageFileBase(PackageFileSystem fileSystem, String relativePath)
    : super(fileSystem, relativePath);

  /**
   * Create a new [Source] instance that serves this file.
   */
  Source createSource([Uri uri]) {
    AnalysisLogger.instance.debug("PackageFileBase(\"${path}\").createSource(${uri == null ? "<null>" : uri})");
    return source;
  }

  WorkspaceSource get source;
}

/**
 * [Folder] implementation of the root folder of a project.
 */
class PackageRootFolder extends PackageFolderBase {
  PackageRootFolder(PackageFileSystem fileSystem)
    : super(fileSystem, "");

  Map<String, List<Folder>> createPackageMap() {
    // Package name => list of source files in the package.
    Map<String, List<WorkspaceSource>> packages = {};

    _fileSystem.sources.forEach((WorkspaceSource source) {
      String packageName = FileUuidHelpers.getPackageFilePackageName(source.uuid);
      List<WorkspaceSource> sources = packages[packageName];
      if (sources == null) {
        sources = [];
        packages[packageName] = sources;
      }
      sources.add(source);
    });

    Map<String, List<Folder>> result = {};
    packages.keys.forEach((String packageName) {
      // Collect set of folder names from source files names
      Set<String> folderNames = new Set<String>();
      packages[packageName].forEach((WorkspaceSource source) {
        String folderName = utils.dirname(FileUuidHelpers.getPackageFileRelativePath(source.uuid));
        folderNames.add(folderName);
      });

      // Create the list of package folders
      List<Folder> folders = folderNames.map((String folderName) =>
          new PackageFolder(_fileSystem, folderName)).toList();
      result[packageName] = folders;
    });
    return result;
  }
}

/**
 * A [Folder] inside a package inside a project.
 */
class PackageFolder extends PackageFolderBase {
  PackageFolder(PackageFileSystem fileSystem, String relativePath)
    : super(fileSystem, relativePath);
}

/**
 * A [File] implementation of a source file in a project.
 */
class PackageFile extends PackageFileBase {
  @override
  final Source source;

  PackageFile(PackageFileSystem fileSystem, String relativePath, this.source)
    : super(fileSystem, relativePath);
}

/**
 * [File] implementation of a project file that does not exist on disk.
 */
class NonExistentPackageFile extends PackageFileBase {
  NonExistentPackageFile(PackageFileSystem fileSystem, String relativePath)
    : super(fileSystem, relativePath);

  @override
  bool get exists => false;

  @override
  Source get source => null;
}
