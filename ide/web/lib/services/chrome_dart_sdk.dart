// Copyright (c) 2014 Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * This library is an entry-point to the Dart analyzer package.
 */
library spark.chrome_dart_sdk;

import 'package:analyzer_clone/src/generated/ast.dart' as ast;
import 'package:analyzer_clone/src/generated/engine.dart';
import 'package:analyzer_clone/src/generated/error.dart';
import 'package:analyzer_clone/src/generated/parser.dart';
import 'package:analyzer_clone/src/generated/scanner.dart';
import 'package:analyzer_clone/src/generated/sdk.dart';
import 'package:analyzer_clone/src/generated/source.dart';

import '../dart/sdk.dart' as sdk;
import 'dart_source.dart';
import 'services_utils.dart' as utils;

/**
 * Create and return a ChromeDartSdk.
 */
ChromeDartSdk createSdk(sdk.DartSdk dartSdk) {
  ChromeDartSdk chromeSdk = new ChromeDartSdk._(dartSdk);
  chromeSdk._parseLibrariesFile();
  return chromeSdk;
}

/**
 * A Spark and Chrome Apps specific implementation of the [DartSdk] class.
 */
class ChromeDartSdk extends DartSdk {
  final AnalysisContext context;

  final sdk.DartSdk _sdk;
  LibraryMap _libraryMap;

  ChromeDartSdk._(this._sdk): context = new AnalysisContextImpl() {
    context.sourceFactory = new SourceFactory([]);
  }

  /**
   * Return a source representing the given `file:` URI if the file is in this SDK,
   * or `null` if the file is not in this SDK.
   */
  @override
  Source fromFileUri(Uri uri) {
    if (uri.scheme != DartUriResolver.DART_SCHEME) {
      return null;
    }

    return mapDartUri(uri.toString());
  }

  /**
   * Return the library representing the library with the given `dart:` URI, or `null`
   * if the given URI does not denote a library in this SDK.
   * The [dartUri] string is expected to have a "dart:library_name" format, for example,
   * "dart:core", "dart:html", etc.
   */
  @override
  SdkLibrary getSdkLibrary(String dartUri) => _libraryMap.getLibrary(dartUri);

  /**
   * Return the source representing the library with the given `dart:`
   * [dartUri], or `null` if the given URI does not denote a library
   * in this SDK.
   *
   * Note: As of version 0.22 of the `analyzer` package, this method
   * must support mapping a simple library uri (e.g "dart:html_common")
   * as well as a libray uri + "/" + a relative path of a file
   * in that library (e.g. "dart:html_common/metadata.dart").
   * In any case, the first part of the URI string (up to the optional "/")
   * is always a library name.
   *
   * Note: This method is mostly a copy-paste of the same method in
   * [DirectoryBasedDartSdk] in the `analyzer` package.
   */
  @override
  Source mapDartUri(String dartUri) {
    // The URI scheme is always "dart"
    Uri uri = utils.parseUriWithException(dartUri);
    assert(uri.scheme == DartUriResolver.DART_SCHEME);

    // The string up to "/" is the library name, the rest (optional)
    // is the relative path of the source file in that library.
    int index = dartUri.indexOf("/");
    String libraryName;
    String relativePath;
    if (index < 0) {
      libraryName = dartUri;
      relativePath = "";
    } else {
      libraryName = dartUri.substring(0, index);
      relativePath = dartUri.substring(index + 1);
    }

    SdkLibrary library = getSdkLibrary(libraryName);
    if (library == null) {
      return null;
    }

    // If we have a relative path, the actual path of the source file
    // is the directory component of the main source file of the library
    // concatenated to the relative path of this source file.
    String path = library.path;
    if (relativePath.isNotEmpty) {
      path = utils.dirname(path) + "/" + relativePath;
    }
    return new SdkSource(_sdk, uri, path);
  }

  @override
  List<SdkLibrary> get sdkLibraries => _libraryMap.sdkLibraries;

  @override
  String get sdkVersion => _sdk.version;

  @override
  List<String> get uris => _libraryMap.uris;

  void _parseLibrariesFile() {
    String contents = _sdk.getSourceForPath('_internal/libraries.dart');
    _libraryMap = _parseLibrariesMap(contents);
  }

  LibraryMap _parseLibrariesMap(String contents) {
    SimpleAnalysisErrorListener errorListener =
        new SimpleAnalysisErrorListener();
    Source source = new StringSource(contents, 'lib/_internal/libraries.dart');
    Scanner scanner =
        new Scanner(source, new CharSequenceReader(contents), errorListener);
    Parser parser = new Parser(source, errorListener);
    ast.CompilationUnit unit = parser.parseCompilationUnit(scanner.tokenize());
    SdkLibrariesReader_LibraryBuilder libraryBuilder =
        new SdkLibrariesReader_LibraryBuilder(false);

    if (!errorListener.foundError) {
      unit.accept(libraryBuilder);
    }
    return libraryBuilder.librariesMap;
  }
}

/**
 * A [Source] implementation based of a file in the SDK.
 */
class SdkSource extends Source {
  final sdk.DartSdk _sdk;
  /**
   * The URI from which this source was originally derived.
   * (e.g. "dart:core")
   */
  final Uri uri;
  /**
   * The path of the "main" source file of the library (e.g. "core/core.dart").
   */
  final String fullName;

  SdkSource(this._sdk, this.uri, this.fullName);

  @override
  bool operator==(Object object) {
    if (object is SdkSource) {
      return object.fullName == fullName;
    } else {
      return false;
    }
  }

  @override
  bool exists() => true;

  @override
  TimestampedData<String> get contents {
    String source = _sdk.getSourceForPath(fullName);
    if (source == null) {
      return null;
    }
    return new TimestampedData<String>(modificationStamp, source);
  }

  void getContentsToReceiver(Source_ContentReceiver receiver) {
    final cnt = contents;

    if (cnt != null) {
      receiver.accept(cnt.data, cnt.modificationTime);
    } else {
      // TODO(devoncarew): Error type seems wrong.
      throw new UnimplementedError('getContentsToReceiver');
    }
  }

  @override
  String get encoding => 'UTF-8';

  @override
  String get shortName => utils.basename(fullName);

  @override
  UriKind get uriKind => UriKind.DART_URI;

  @override
  int get hashCode => fullName.hashCode;

  @override
  bool get isInSystemLibrary => true;

  @override
  Uri resolveRelativeUri(Uri relativeUri) =>
      resolveRelativeUriHelper(uri, relativeUri);

  @override
  int get modificationStamp => 0;

  @override
  String toString() => "SdkSource(uri='${uri}', fullName='${fullName}')";
}

class SimpleAnalysisErrorListener implements AnalysisErrorListener {
  bool foundError = false;

  SimpleAnalysisErrorListener();

  @override
  void onError(AnalysisError error) {
    foundError = true;
  }
}
