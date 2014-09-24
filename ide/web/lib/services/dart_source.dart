// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.dart_source;

import 'package:analyzer_clone/src/generated/engine.dart';
import 'package:analyzer_clone/src/generated/source.dart';

import 'services_utils.dart' as utils;

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
