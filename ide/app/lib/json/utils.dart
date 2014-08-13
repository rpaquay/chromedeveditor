// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.utils;

import 'json_parser.dart';
import 'json_validator.dart';
import '../workspace.dart';

// Representation of a (Line, Column) pair, both 1-based.
class LineColumn {
  final int line;
  final int column;
  LineColumn(this.line, this.column);
}

// Utility class for converting between offsets and (line,column) positions
// for a string containing newline characters.
class StringLineOffsets {
  final String contents;
  List<int> lineOffsets;

  StringLineOffsets(this.contents);

  LineColumn getLineColumn(int position) {
    int lineNumber = _calcLineNumber(position);
    int columnNumber = 0;
    if (lineNumber < lineOffsets.length) {
      columnNumber = position - lineOffsets[lineNumber];
    }
    
    return new LineColumn(lineNumber + 1, columnNumber + 1);
  }
  
  /**
   * Count the newlines between 0 and position.
   */
  int _calcLineNumber(int position) {
   if (lineOffsets == null)
     lineOffsets = _createLineOffsets(contents);
   
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

// Implement of ErrorSink for a [File] instance.
class FileErrorSink implements ErrorSink {
  final File file;
  final String markerType;
  final int markerSeverity;
  /*final*/ StringLineOffsets lineOffsets;

  FileErrorSink(this.file, String contents, this.markerType, this.markerSeverity) {
    this.lineOffsets = new StringLineOffsets(contents);    
    file.clearMarkers(markerType);
  }

  void emitMessage(Span span, String message) {
    LineColumn startPos = lineOffsets.getLineColumn(span.start);
    file.createMarker(markerType, markerSeverity, message, startPos.line, span.start, span.end);
  }
}
