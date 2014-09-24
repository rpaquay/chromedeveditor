// Copyright (c) 2013, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * This library is an entry-point to the Dart analyzer package.
 */
library spark.analyzer;

import 'dart:async';

import 'package:analyzer_clone/src/generated/ast.dart' as ast;
import 'package:analyzer_clone/src/generated/element.dart' as elements;
import 'package:analyzer_clone/src/generated/engine.dart';
import 'package:analyzer_clone/src/generated/error.dart';
import 'package:analyzer_clone/src/generated/sdk.dart';
import 'package:analyzer_clone/src/generated/source.dart';

export 'package:analyzer_clone/src/generated/ast.dart';
export 'package:analyzer_clone/src/generated/element.dart';
export 'package:analyzer_clone/src/generated/error.dart';
export 'package:analyzer_clone/src/generated/source.dart';

import 'chrome_dart_sdk.dart';
import 'dart_services.dart';
import 'dart_source.dart';
import 'outline_builder.dart';
import 'services_common.dart' as common;
import 'services_utils.dart' as utils;
import '../dart/sdk.dart' as sdk;

/**
 * Implementation of [DartServices] using the [analyzer] package.
 */
class AnalyzerDartServices implements DartServices {
  final ChromeDartSdk dartSdk;
  final common.ContentsProvider _contentsProvider;
  final Map<String, ProjectContext> _contexts = {};

  AnalyzerDartServices(sdk.DartSdk sdk, this._contentsProvider)
    : dartSdk = createSdk(sdk);

  Future<ChromeDartSdk> get dartSdkFuture => new Future.value(dartSdk);

  @override
  Future<common.Outline> getOutlineFor(String codeString) {
    return analyzeString(dartSdk, codeString).then((AnalyzerResult result) {
      return new OutlineBuilder().build(result.ast);
    });
  }

  @override
  Future createContext(String id) {
    _contexts[id] = new ProjectContext(id, dartSdk, _contentsProvider);
    return new Future.value(null);
  }

  @override
  Future<AnalysisResultUuid> processContextChanges(
      String id,
      List<String> addedUuids,
      List<String> changedUuids,
      List<String> deletedUuids) {
    ProjectContext context = _contexts[id];

    if (context == null) {
      return new Future.error('no context associated with id ${id}');
    }

    return context.processChanges(addedUuids, changedUuids, deletedUuids);
  }

  @override
  Future disposeContext(String id) {
    _contexts.remove(id);
    return new Future.value(null);
  }

  @override
  Future<common.Declaration> getDeclarationFor(String contextId, String fileUuid, int offset) {
    ProjectContext context = _contexts[contextId];

    if (context == null) {
      return new Future.error('no context associated with id ${contextId}');
    }

    common.Declaration declaration = new DeclarationBuilder().build(context, fileUuid, offset);
    return new Future.value(declaration);
  }
}

class DeclarationBuilder {
  common.Declaration build(
      ProjectContext context, String fileUuid, int offset) {
    WorkspaceSource source = context.getSource(fileUuid);

    List<Source> librarySources =
        context.context.getLibrariesContaining(source);

    if (librarySources.isEmpty) return null;

    ast.CompilationUnit compilationUnit =
        context.context.resolveCompilationUnit2(source, librarySources[0]);

    ast.AstNode node =
        new ast.NodeLocator.con1(offset).searchWithin(compilationUnit);

    // Handle import and export directives.
    if (node is ast.SimpleStringLiteral &&
        node.parent is ast.NamespaceDirective) {
      ast.SimpleStringLiteral literal = node;
      ast.NamespaceDirective directive = node.parent;
      if (directive.source is WorkspaceSource) {
        WorkspaceSource fileSource = directive.source;
        return new common.SourceDeclaration(literal.value, fileSource.uuid, 0, 0);
      } else {
        // TODO(ericarnold): Handle SDK import
        return null;
      }
    }

    if (node is! ast.SimpleIdentifier) return null;

    elements.Element element = ast.ElementLocator.locate(node);
    if (element == null) return null;

    if (element.nameOffset == -1) {
      if (element is elements.ConstructorElement) {
        elements.ConstructorElement constructorElement = element;
        element = constructorElement.enclosingElement;
      } else if (element.source == null) {
        return null;
      }
    }

    if (element.source is WorkspaceSource) {
      WorkspaceSource fileSource = element.source;
      return new common.SourceDeclaration(element.displayName, fileSource.uuid,
          element.nameOffset, element.name.length);
    } else if (element.source is SdkSource) {
      String url = _getUrlForElement(element);
      if (url == null) return null;
      return new common.DocDeclaration(element.displayName, url);
    } else {
      return null;
    }
  }

  /**
   * Convert a dart: library reference into the corresponding dartdoc url.
   */
  String _getUrlForElement(elements.Element element) {
    SdkSource sdkSource = element.source;
    String libraryName = element.library.name.replaceAll(".", "-");
    String baseUrl =
        "https://api.dartlang.org/apidocs/channels/stable/dartdoc-viewer";
    String className;
    String memberAnchor = "";
    elements.Element enclosingElement = element.enclosingElement;
    if (element is elements.ClassElement) {
      className = element.name;
    } else if (enclosingElement is elements.ClassElement) {
      className = enclosingElement.name;
      memberAnchor = "#id_${element.name}";
    } else {
      // TODO: Top level variables and functions
      return null;
    }

    return "$baseUrl/$libraryName.$className$memberAnchor";
  }
}

/**
 * Logger specific to this library.
 */
abstract class _DebugLogger {
  /// Switch between `null` and [print] logger implementations.
  static _DebugLogger instance = new _NullDebugLogger();
  //static _DebugLogger instance = new _PrintDebugLogger();

  void debug(String message);
}

/**
 * Default `null` logger.
 */
class _NullDebugLogger implements _DebugLogger {
  void debug(String message) => null;
}

/**
 * Logger forwarding messages to the [print] method.
 */
class _PrintDebugLogger implements _DebugLogger {
  void debug(String message) => print(message);
}

/**
 * Logger for the analysis engine messages, forwards all calls to
 * [_DebugLogger.instance].
 */
class _AnalysisEngineDebugLogger implements Logger {
  @override
  void logError(String message) =>
    _DebugLogger.instance.debug("[analyzer] error: ${message}");

  @override
  void logError2(String message, Exception exception) =>
    _DebugLogger.instance.debug("[analyzer] error: ${message} ${exception}");

  @override
  void logInformation(String message) =>
    _DebugLogger.instance.debug("[analyzer] info: ${message}");

  @override
  void logInformation2(String message, Exception exception) =>
    _DebugLogger.instance.debug("[analyzer] info: ${message} ${exception}");
}

/**
 * Given a string representing Dart source, return a result consisting of an AST
 * and a list of errors.
 *
 * The API for this method is asynchronous; the actual implementation is
 * synchronous. In the future both API and implementation will be asynchronous.
 */
Future<AnalyzerResult> analyzeString(ChromeDartSdk sdk, String contents) {
  Completer completer = new Completer();

  AnalysisContext context = AnalysisEngine.instance.createAnalysisContext();
  context.sourceFactory = new SourceFactory([new DartUriResolver(sdk)]);

  ast.CompilationUnit unit;
  StringSource source = new StringSource(contents, '<StringSource>');

  try {
    unit = context.parseCompilationUnit(source);
  } catch (e) {
    unit = null;
  }

  AnalyzerResult result = new AnalyzerResult(unit, context.getErrors(source));

  completer.complete(result);

  return completer.future;
}

/**
 * A tuple of an AST and a list of errors.
 */
class AnalyzerResult {
  final ast.CompilationUnit ast;
  final AnalysisErrorInfo errorInfo;

  AnalyzerResult(this.ast, this.errorInfo);

  List<AnalysisError> get errors => errorInfo.errors;

  LineInfo_Location getLineInfo(AnalysisError error) =>
    errorInfo.lineInfo.getLocation(error.offset);

  String toString() => 'AnalyzerResult[${errorInfo.errors.length} issues]';
}

/**
 * A wrapper around an analysis context. There is a one-to-one mapping between
 * projects, on the DOM side, and analysis contexts.
 */
class ProjectContext {
  static const int MAX_CACHE_SIZE = 256;
  static final int DEFAULT_CACHE_SIZE = AnalysisOptionsImpl.DEFAULT_CACHE_SIZE;

  // The id for the project this context is associated with.
  final String id;
  final ChromeDartSdk sdk;
  final common.ContentsProvider provider;

  AnalysisContext context;

  final Map<String, WorkspaceSource> _sources = {};

  ProjectContext(this.id, this.sdk, this.provider) {
    AnalysisEngine.instance.logger = new _AnalysisEngineDebugLogger();
    context = AnalysisEngine.instance.createAnalysisContext();
    context.sourceFactory = new SourceFactory([
        new DartSdkUriResolver(sdk),
        new PackageUriResolver(this),
        new FileUriResolver(this)
    ]);
  }

  Future<AnalysisResultUuid> processChanges(List<String> addedUuids,
      List<String> changedUuids, List<String> deletedUuids) {

    ChangeSet changeSet = new ChangeSet();

    // added
    for (String uuid in addedUuids) {
      _sources[uuid] = new WorkspaceSource(this, uuid);
      changeSet.addedSource(_sources[uuid]);
    }

    // changed
    for (String uuid in changedUuids) {
      if (_sources[uuid] != null) {
        changeSet.changedSource(_sources[uuid]);
        _sources[uuid].setContents(null);
      } else {
        _sources[uuid] = new WorkspaceSource(this, uuid);
        changeSet.addedSource(_sources[uuid]);
      }
    }

    // deleted
    for (String uuid in deletedUuids) {
      if (_sources[uuid] != null) {
        // TODO(devoncarew): Should we set this to deleted or remove the FileSource?
        _sources[uuid]._exists = false;
        _sources[uuid].setContents(null);
        changeSet.removedSource(_sources.remove(uuid));
      }
    }

    // Increase the cache size before we process the changes. We set the size
    // back down to the default after analysis is complete.
    _setCacheSize(MAX_CACHE_SIZE);

    context.applyChanges(changeSet);

    Completer<AnalysisResultUuid> completer = new Completer();

    _populateSources().then((_) {
      _processChanges(completer, new AnalysisResultUuid());
    }).catchError((e) {
      _setCacheSize(DEFAULT_CACHE_SIZE);
      completer.completeError(e);
    });

    return completer.future;
  }

  WorkspaceSource getSource(String uuid) {
    return _sources[uuid];
  }

  void _processChanges(Completer<AnalysisResultUuid> completer,
      AnalysisResultUuid analysisResult) {
    try {
      AnalysisResult result = context.performAnalysisTask();
      List<ChangeNotice> notices = result.changeNotices;

      while (notices != null) {
        for (ChangeNotice notice in notices) {
          if (notice.source is! WorkspaceSource) continue;

          WorkspaceSource source = notice.source;
          analysisResult.addErrors(
              source.uuid, _convertErrors(notice, notice.errors));
        }

        result = context.performAnalysisTask();
        notices = result.changeNotices;
      }

      _setCacheSize(DEFAULT_CACHE_SIZE);
      completer.complete(analysisResult);
    } catch (e, st) {
      _setCacheSize(DEFAULT_CACHE_SIZE);
      completer.completeError(e, st);
    }
  }

  /**
   * Populate the contents for the [WorkspaceSource]s.
   */
  Future _populateSources() {
    List<Future> futures = [];

    _sources.forEach((String uuid, WorkspaceSource source) {
      if (source.exists() && source._strContents == null) {
        Future f;

        if (uuid.startsWith('package:')) {
          f = provider.getPackageContents(id, uuid).then((String str) {
            source.setContents(str);
          });
        } else {
          f = provider.getFileContents(uuid).then((String str) {
            source.setContents(str);
          });
        }

        futures.add(f);
      }
    });

    return Future.wait(futures);
  }

  void _setCacheSize(int size) {
    var options = new AnalysisOptionsImpl();
    options.cacheSize = size;
    context.analysisOptions = options;
  }
}

List<common.AnalysisError> _convertErrors(
    AnalysisErrorInfo errorInfo, List<AnalysisError> errors) {
  return errors.map((error) => _convertError(errorInfo, error)).toList();
}

common.AnalysisError _convertError(AnalysisErrorInfo errorInfo, AnalysisError error) {
  common.AnalysisError err = new common.AnalysisError();
  err.message = error.message;
  err.offset = error.offset;
  LineInfo_Location location = errorInfo.lineInfo.getLocation(error.offset);
  err.lineNumber = location.lineNumber;
  err.length = error.length;
  err.errorSeverity = _errorSeverityToInt(error.errorCode.errorSeverity);
  return err;
}

int _errorSeverityToInt(ErrorSeverity severity) {
  if (severity == ErrorSeverity.ERROR) {
    return common.ErrorSeverity.ERROR;
  } else  if (severity == ErrorSeverity.WARNING) {
    return common.ErrorSeverity.WARNING;
  } else  if (severity == ErrorSeverity.INFO) {
    return common.ErrorSeverity.INFO;
  } else {
    return common.ErrorSeverity.NONE;
  }
}

/**
 * A [Source] abstract base class based on workspace uuids.
 */
abstract class WorkspaceSource extends Source {
  static final FILE_SCHEME = "file";
  static final PACKAGE_SCHEME = "package";
  ProjectContext context;
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
  factory WorkspaceSource(ProjectContext context, String uuid) {
    assert(uuid != null);
    if (uuid.startsWith(PACKAGE_SCHEME + ":")) {
      return new PackageSource(context, uuid);
    } else {
      return new FileSource(context, uuid);
    }
  }

  WorkspaceSource._(this.context, this.uuid) {
    touchFile();
  }

  @override
  bool operator==(Object object) {
    return object is WorkspaceSource ? object.uuid == uuid : false;
  }

  @override
  bool exists() => _exists;

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

  void setContents(String newContents) {
    _strContents = newContents;
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
  PackageSource(ProjectContext context, String uuid): super._(context, uuid) {
    _DebugLogger.instance.debug("PackageSource(${uuid})");
  }

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
  FileSource(ProjectContext context, String uuid): super._(context, uuid) {
    _DebugLogger.instance.debug("FileSource(${uuid})");
  }

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

/**
 * [UriResolver] implementation for the "dart" URI scheme.
 */
class DartSdkUriResolver extends DartUriResolver {
  DartSdkUriResolver(DartSdk sdk) : super(sdk);

  /**
   * Return the source representing the SDK source file with the given `dart:`
   * [uri], or `null` if the given URI does not denote a file in the SDK.
   *
   * Notes:
   * * The scheme is expected to be "dart:".
   * * The path is formed of the library name (e.g. "core") optionally followed
   *   by a "/" and the path of the source file in the library (e.g. "core.dart",
   *   "bool.dart").
   * * This methods ends up calling [ChromeDartSdk.mapDartUri].
   */
  @override
  Source resolveAbsolute(Uri uri) => super.resolveAbsolute(uri);
}

/**
 * [UriResolver] implementation for the "file" URI scheme.
 */
class FileUriResolver extends UriResolver {
  static String FILE_SCHEME = "file";

  static bool isFileUri(Uri uri) => uri.scheme == FILE_SCHEME;

  final ProjectContext context;

  FileUriResolver(this.context);

  @override
  Source resolveAbsolute(Uri uri) {
    if (!isFileUri(uri)) {
      return null;
    }

    // TODO(rpaquay): This is somewhat brittle, as this relies on the specific
    // format of [uuid] returned by the Workspace implementation.
    // Example:
    //   context.id = "chrome-app-id:application-name"
    //   uri.path = "path-to-source-file-within-chrome-app"
    String uuid = utils.pathconcat(context.id, uri.path);
    return context.getSource(uuid);
  }
}

/**
 * [UriResolver] implementation for the "package" URI scheme.
 */
class PackageUriResolver extends UriResolver {
  static String PACKAGE_SCHEME = "package";

  static bool isPackageUri(Uri uri) => uri.scheme == PACKAGE_SCHEME;

  final ProjectContext context;

  PackageUriResolver(this.context);

  /**
   * Resolve the given absolute URI. Return a [Source] representing the file to
   * which it was resolved, whether or not the resulting source exists,
   * or `null` if it could not be resolved because the URI is invalid.
   */
  @override
  Source resolveAbsolute(Uri uri) {
    if (!isPackageUri(uri)) {
      return null;
    }
    return context.getSource(uri.toString());
  }
}
