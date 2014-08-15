// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.utils;

// Representation of a (Line, Column) pair, both 1-based.
class LineColumn {
  final int line;
  final int column;
  LineColumn(this.line, this.column) {
    assert(line >= 1);
    assert(column >= 1);
  }
}

// Utility class for converting between offsets and (line,column) positions
// for a string containing newline characters.
class StringLineOffsets {
  final String contents;
  List<int> lineOffsets;

  StringLineOffsets(this.contents);

  /**
   * Returns a 1-based [LineColumn] instances from an offset [position].
   */
  LineColumn getLineColumn(int position) {
    int lineIndex = _calcLineIndex(position);
    int columnIndex = position - lineOffsets[lineIndex];
    return new LineColumn(lineIndex + 1, columnIndex + 1);
  }

  /**
   * Counts the newlines between 0 and position.
   */
  int _calcLineIndex(int position) {
    assert(position >= 0);
    if (lineOffsets == null)
      lineOffsets = _createLineOffsets(contents);

    int lineIndex = _binarySearch(lineOffsets, position);
    if (lineIndex < 0) {
      // Note: we need "- 1" because the binary search returns the
      // insertion index of [position], while we are interested
      // in the line containing [position].
      lineIndex = (~lineIndex) - 1;
    }
    assert(lineIndex >= 0 && lineIndex < lineOffsets.length);
    return lineIndex;
  }

  /**
   * Returns the position of [item] in [items] if present.
   * Returns the bitwise complement (~) of the insertion position if [item] is
   * not found.
   */
  static int _binarySearch(List items, var item) {
   int min = 0;
   int max = items.length - 1;
   while (min <= max) {
     int med = (min + max) ~/ 2;
     if (items[med] < item)
       min = med + 1;
     else if (items[med] > item)
       max = med - 1;
     else
       return med;
   }
   return ~min;
  }

  /**
   * Creates a sorted array of positions where line starts in [source].
   * The first element of the returned array is always 0.
   * TODO(rpaquay): This should be part of [File] maybe?
   */
  static List<int> _createLineOffsets(String source) {
   List<int> result = new List<int>();
   result.add(0);  // first line always starts at offset 0
   for (int index = 0; index < source.length; index++) {
     // TODO(rpaquay): Are there other characters to consider as "end of line".
     if (source[index] == '\n') {
       result.add(index + 1);
     }
   }
   return result;
  }
}
