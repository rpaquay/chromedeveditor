// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.services_utils;

/**
 * Returns the filename part of [path].
 */
String basename(String path) {
  int index = path.lastIndexOf('/');
  return index == -1 ? path : path.substring(index + 1);
}

/**
 * Returns the directory name part of [path].
 */
String dirname(String path) {
  int index = path.lastIndexOf('/');
  return index == -1 ? '' : path.substring(0, index);
}

String pathconcat(String path1, String path2) {
  if (path1.isEmpty) {
    return path2;
  }
  if (path2.isEmpty){
    return path1;
  }
  if (path1.endsWith("/") || path2.startsWith("/")) {
    return path1 + path2;
  }
  return path1 + "/" + path2;
}

/**
 * Note: this code is mostly a copy-paste of the function with
 * the same name in `package:analyzer/generated/java_core.dart`.
 */
Uri parseUriWithException(String str) {
  Uri uri = Uri.parse(str);
  if (uri.path.isEmpty) {
    throw new URISyntaxException();
  }
  return uri;
}

class URISyntaxException implements Exception {
  String toString() => "URISyntaxException";
}
