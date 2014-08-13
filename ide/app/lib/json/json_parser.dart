// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Note: The parser implementation is based on the deprecated
// "package:json/json.dart" implementation. It has been modifed
// to expose source span information when parsing elements.

library json_parser;

//// Implementation ///////////////////////////////////////////////////////////

// Straightfoward span representation.
class Span {
  int start; // Start position (inclusive)
  int end; // End position (inclusive)
  Span(this.start, this.end);
}

// Simple API for JSON parsing.
abstract class JsonListener {
  void handleString(Span span, String value) {}
  void handleNumber(Span span, num value) {}
  void handleBool(Span span, bool value) {}
  void handleNull(Span span) {}
  void beginObject(int position) {}
  void propertyName(Span span) {}
  void propertyValue(Span span) {}
  void endObject(Span span) {}
  void beginArray(int position) {}
  void arrayElement(Span span) {}
  void endArray(Span span) {}
  /** Called on failure to parse [source]. */
  void fail(String source, Span span, String message) {}
}

class SpanState {
  List<int> startPositions = <int>[];
  List<int> endPositions = <int>[];

  void enter(int position) {
    assert(startPositions.length >= endPositions.length);
    startPositions.add(position);
  }

  void leave(int position) {
    assert(startPositions.length >= endPositions.length);
    assert(startPositions.length > 0);
    endPositions.add(position);
  }

  Span pop() {
    assert(startPositions.length > 0);
    assert(endPositions.length > 0);
    assert(startPositions.length >= endPositions.length);
    int start = startPositions.removeLast();
    int end = endPositions.removeLast();
    return new Span(start, end);
  }
}

class JsonParser {
  // A simple non-recursive state-based parser for JSON.
  //
  // Literal values accepted in states ARRAY_EMPTY, ARRAY_COMMA, OBJECT_COLON
  // and strings also in OBJECT_EMPTY, OBJECT_COMMA.
  //               VALUE  STRING  :  ,  }  ]        Transitions to
  // EMPTY            X      X                   -> END
  // ARRAY_EMPTY      X      X             @     -> ARRAY_VALUE / pop
  // ARRAY_VALUE                     @     @     -> ARRAY_COMMA / pop
  // ARRAY_COMMA      X      X                   -> ARRAY_VALUE
  // OBJECT_EMPTY            X          @        -> OBJECT_KEY / pop
  // OBJECT_KEY                   @              -> OBJECT_COLON
  // OBJECT_COLON     X      X                   -> OBJECT_VALUE
  // OBJECT_VALUE                    @  @        -> OBJECT_COMMA / pop
  // OBJECT_COMMA            X                   -> OBJECT_KEY
  // END
  // Starting a new array or object will push the current state. The "pop"
  // above means restoring this state and then marking it as an ended value.
  // X means generic handling, @ means special handling for just that
  // state - that is, values are handled generically, only punctuation
  // cares about the current state.
  // Values for states are chosen so bits 0 and 1 tell whether
  // a string/value is allowed, and setting bits 0 through 2 after a value
  // gets to the next state (not empty, doesn't allow a value).

  // State building-block constants.
  static const int INSIDE_ARRAY = 1;
  static const int INSIDE_OBJECT = 2;
  static const int AFTER_COLON = 3; // Always inside object.

  static const int ALLOW_STRING_MASK = 8; // Allowed if zero.
  static const int ALLOW_VALUE_MASK = 4; // Allowed if zero.
  static const int ALLOW_VALUE = 0;
  static const int STRING_ONLY = 4;
  static const int NO_VALUES = 12;

  // Objects and arrays are "empty" until their first property/element.
  static const int EMPTY = 0;
  static const int NON_EMPTY = 16;
  static const int EMPTY_MASK = 16; // Empty if zero.


  static const int VALUE_READ_BITS = NO_VALUES | NON_EMPTY;

  // Actual states.
  static const int STATE_INITIAL = EMPTY | ALLOW_VALUE;
  static const int STATE_END = NON_EMPTY | NO_VALUES;

  static const int STATE_ARRAY_EMPTY = INSIDE_ARRAY | EMPTY | ALLOW_VALUE;
  static const int STATE_ARRAY_VALUE = INSIDE_ARRAY | NON_EMPTY | NO_VALUES;
  static const int STATE_ARRAY_COMMA = INSIDE_ARRAY | NON_EMPTY | ALLOW_VALUE;

  static const int STATE_OBJECT_EMPTY = INSIDE_OBJECT | EMPTY | STRING_ONLY;
  static const int STATE_OBJECT_KEY = INSIDE_OBJECT | NON_EMPTY | NO_VALUES;
  static const int STATE_OBJECT_COLON = AFTER_COLON | NON_EMPTY | ALLOW_VALUE;
  static const int STATE_OBJECT_VALUE = AFTER_COLON | NON_EMPTY | NO_VALUES;
  static const int STATE_OBJECT_COMMA = INSIDE_OBJECT | NON_EMPTY | STRING_ONLY;

  // Character code constants.
  static const int BACKSPACE = 0x08;
  static const int TAB = 0x09;
  static const int NEWLINE = 0x0a;
  static const int CARRIAGE_RETURN = 0x0d;
  static const int FORM_FEED = 0x0c;
  static const int SPACE = 0x20;
  static const int QUOTE = 0x22;
  static const int PLUS = 0x2b;
  static const int COMMA = 0x2c;
  static const int MINUS = 0x2d;
  static const int DECIMALPOINT = 0x2e;
  static const int SLASH = 0x2f;
  static const int CHAR_0 = 0x30;
  static const int CHAR_9 = 0x39;
  static const int COLON = 0x3a;
  static const int CHAR_E = 0x45;
  static const int LBRACKET = 0x5b;
  static const int BACKSLASH = 0x5c;
  static const int RBRACKET = 0x5d;
  static const int CHAR_a = 0x61;
  static const int CHAR_b = 0x62;
  static const int CHAR_e = 0x65;
  static const int CHAR_f = 0x66;
  static const int CHAR_l = 0x6c;
  static const int CHAR_n = 0x6e;
  static const int CHAR_r = 0x72;
  static const int CHAR_s = 0x73;
  static const int CHAR_t = 0x74;
  static const int CHAR_u = 0x75;
  static const int LBRACE = 0x7b;
  static const int RBRACE = 0x7d;

  final String source;
  final JsonListener listener;
  JsonParser(this.source, this.listener);

  /** Parses [source], or throws if it fails. */
  void parse() {
    final List<int> states = <int>[];
    int state = STATE_INITIAL;
    SpanState spanState = new SpanState();
    int position = 0;
    int length = source.length;
    while (position < length) {
      int char = source.codeUnitAt(position);
      switch (char) {
        case SPACE:
        case CARRIAGE_RETURN:
        case NEWLINE:
        case TAB:
          position++;
          break;
        case QUOTE:
          if ((state & ALLOW_STRING_MASK) != 0) fail(position);
          spanState.enter(position);
          position = parseString(position + 1);
          spanState.leave(position);
          state |= VALUE_READ_BITS;
          break;
        case LBRACKET:
          if ((state & ALLOW_VALUE_MASK) != 0) fail(position);
          spanState.enter(position);
          listener.beginArray(position);
          states.add(state);
          state = STATE_ARRAY_EMPTY;
          position++;
          break;
        case LBRACE:
          if ((state & ALLOW_VALUE_MASK) != 0) fail(position);
          spanState.enter(position);
          listener.beginObject(position);
          states.add(state);
          state = STATE_OBJECT_EMPTY;
          position++;
          break;
        case CHAR_n:
          if ((state & ALLOW_VALUE_MASK) != 0) fail(position);
          spanState.enter(position);
          position = parseNull(position);
          spanState.leave(position);
          state |= VALUE_READ_BITS;
          break;
        case CHAR_f:
          if ((state & ALLOW_VALUE_MASK) != 0) fail(position);
          spanState.enter(position);
          position = parseFalse(position);
          spanState.leave(position);
          state |= VALUE_READ_BITS;
          break;
        case CHAR_t:
          if ((state & ALLOW_VALUE_MASK) != 0) fail(position);
          spanState.enter(position);
          position = parseTrue(position);
          spanState.leave(position);
          state |= VALUE_READ_BITS;
          break;
        case COLON:
          if (state != STATE_OBJECT_KEY) fail(position);
          listener.propertyName(spanState.pop());
          state = STATE_OBJECT_COLON;
          position++;
          break;
        case COMMA:
          if (state == STATE_OBJECT_VALUE) {
            listener.propertyValue(spanState.pop());
            state = STATE_OBJECT_COMMA;
            position++;
          } else if (state == STATE_ARRAY_VALUE) {
            listener.arrayElement(spanState.pop());
            state = STATE_ARRAY_COMMA;
            position++;
          } else {
            fail(position);
          }
          break;
        case RBRACKET:
          if (state == STATE_ARRAY_EMPTY) {
            spanState.leave(position);
            listener.endArray(spanState.pop());
          } else if (state == STATE_ARRAY_VALUE) {
            listener.arrayElement(spanState.pop());
            spanState.leave(position);
            listener.endArray(spanState.pop());
          } else {
            spanState.leave(position);
            spanState.pop();
            fail(position);
          }
          state = states.removeLast() | VALUE_READ_BITS;
          position++;
          break;
        case RBRACE:
          if (state == STATE_OBJECT_EMPTY) {
            spanState.leave(position);
            listener.endObject(spanState.pop());
          } else if (state == STATE_OBJECT_VALUE) {
            listener.propertyValue(spanState.pop());
            spanState.leave(position);
            listener.endObject(spanState.pop());
          } else {
            spanState.leave(position);
            failSpan(spanState.pop());
          }
          state = states.removeLast() | VALUE_READ_BITS;
          position++;
          break;
        default:
          if ((state & ALLOW_VALUE_MASK) != 0) fail(position);
          spanState.enter(position);
          position = parseNumber(char, position);
          spanState.leave(position);
          state |= VALUE_READ_BITS;
          break;
      }
    }
    if (state != STATE_END) fail(position);
  }

  /**
   * Parses a "true" literal starting at [position].
   *
   * [:source[position]:] must be "t".
   */
  int parseTrue(int position) {
    assert(source.codeUnitAt(position) == CHAR_t);
    if (source.length < position + 4) fail(position, "Unexpected identifier");
    if (source.codeUnitAt(position + 1) != CHAR_r || source.codeUnitAt(position + 2) != CHAR_u || source.codeUnitAt(position + 3) != CHAR_e) {
      fail(position);
    }
    listener.handleBool(new Span(position, position + 4), true);
    return position + 4;
  }

  /**
   * Parses a "false" literal starting at [position].
   *
   * [:source[position]:] must be "f".
   */
  int parseFalse(int position) {
    assert(source.codeUnitAt(position) == CHAR_f);
    if (source.length < position + 5) fail(position, "Unexpected identifier");
    if (source.codeUnitAt(position + 1) != CHAR_a || source.codeUnitAt(position + 2) != CHAR_l || source.codeUnitAt(position + 3) != CHAR_s || source.codeUnitAt(position + 4) != CHAR_e) {
      fail(position);
    }
    listener.handleBool(new Span(position, position + 4), false);
    return position + 5;
  }

  /** Parses a "null" literal starting at [position].
   *
   * [:source[position]:] must be "n".
   */
  int parseNull(int position) {
    assert(source.codeUnitAt(position) == CHAR_n);
    if (source.length < position + 4) fail(position, "Unexpected identifier");
    if (source.codeUnitAt(position + 1) != CHAR_u || source.codeUnitAt(position + 2) != CHAR_l || source.codeUnitAt(position + 3) != CHAR_l) {
      fail(position);
    }
    listener.handleNull(new Span(position, position + 4));
    return position + 4;
  }

  int parseString(int position) {
    // Format: '"'([^\x00-\x1f\\\"]|'\\'[bfnrt/\\"])*'"'
    // Initial position is right after first '"'.
    int start = position;
    int char;
    do {
      if (position == source.length) {
        fail(start - 1, "Unterminated string");
      }
      char = source.codeUnitAt(position);
      if (char == QUOTE) {
        listener.handleString(new Span(start, position), source.substring(start, position));
        return position + 1;
      }
      if (char < SPACE) {
        fail(position, "Control character in string");
      }
      position++;
    } while (char != BACKSLASH);
    // Backslash escape detected. Collect character codes for rest of string.
    int firstEscape = position - 1;
    List<int> chars = <int>[];
    while (true) {
      if (position == source.length) {
        fail(start - 1, "Unterminated string");
      }
      char = source.codeUnitAt(position);
      switch (char) {
        case CHAR_b:
          char = BACKSPACE;
          break;
        case CHAR_f:
          char = FORM_FEED;
          break;
        case CHAR_n:
          char = NEWLINE;
          break;
        case CHAR_r:
          char = CARRIAGE_RETURN;
          break;
        case CHAR_t:
          char = TAB;
          break;
        case SLASH:
        case BACKSLASH:
        case QUOTE:
          break;
        case CHAR_u:
          int hexStart = position - 1;
          int value = 0;
          for (int i = 0; i < 4; i++) {
            position++;
            if (position == source.length) {
              fail(start - 1, "Unterminated string");
            }
            char = source.codeUnitAt(position);
            char -= 0x30;
            if (char < 0) fail(hexStart, "Invalid unicode escape");
            if (char < 10) {
              value = value * 16 + char;
            } else {
              char = (char | 0x20) - 0x31;
              if (char < 0 || char > 5) {
                fail(hexStart, "Invalid unicode escape");
              }
              value = value * 16 + char + 10;
            }
          }
          char = value;
          break;
        default:
          if (char < SPACE) fail(position, "Control character in string");
          fail(position, "Unrecognized string escape");
      }
      do {
        chars.add(char);
        position++;
        if (position == source.length) fail(start - 1, "Unterminated string");
        char = source.codeUnitAt(position);
        if (char == QUOTE) {
          String result = new String.fromCharCodes(chars);
          if (start < firstEscape) {
            result = "${source.substring(start, firstEscape)}$result";
          }
          listener.handleString(new Span(start, position), result);
          return position + 1;
        }
        if (char < SPACE) {
          fail(position, "Control character in string");
        }
      } while (char != BACKSLASH);
      position++;
    }
  }

  int _handleLiteral(start, position, isDouble) {
    String literal = source.substring(start, position);
    // This correctly creates -0 for doubles.
    num value = (isDouble ? double.parse(literal) : int.parse(literal));
    listener.handleNumber(new Span(start, position), value);
    return position;
  }

  int parseNumber(int char, int position) {
    // Format:
    //  '-'?('0'|[1-9][0-9]*)('.'[0-9]+)?([eE][+-]?[0-9]+)?
    int start = position;
    int length = source.length;
    bool isDouble = false;
    if (char == MINUS) {
      position++;
      if (position == length) fail(position, "Missing expected digit");
      char = source.codeUnitAt(position);
    }
    if (char < CHAR_0 || char > CHAR_9) {
      fail(position, "Missing expected digit");
    }
    if (char == CHAR_0) {
      position++;
      if (position == length) return _handleLiteral(start, position, false);
      char = source.codeUnitAt(position);
      if (CHAR_0 <= char && char <= CHAR_9) {
        fail(position);
      }
    } else {
      do {
        position++;
        if (position == length) return _handleLiteral(start, position, false);
        char = source.codeUnitAt(position);
      } while (CHAR_0 <= char && char <= CHAR_9);
    }
    if (char == DECIMALPOINT) {
      isDouble = true;
      position++;
      if (position == length) fail(position, "Missing expected digit");
      char = source.codeUnitAt(position);
      if (char < CHAR_0 || char > CHAR_9) fail(position);
      do {
        position++;
        if (position == length) return _handleLiteral(start, position, true);
        char = source.codeUnitAt(position);
      } while (CHAR_0 <= char && char <= CHAR_9);
    }
    if (char == CHAR_e || char == CHAR_E) {
      isDouble = true;
      position++;
      if (position == length) fail(position, "Missing expected digit");
      char = source.codeUnitAt(position);
      if (char == PLUS || char == MINUS) {
        position++;
        if (position == length) fail(position, "Missing expected digit");
        char = source.codeUnitAt(position);
      }
      if (char < CHAR_0 || char > CHAR_9) {
        fail(position, "Missing expected digit");
      }
      do {
        position++;
        if (position == length) return _handleLiteral(start, position, true);
        char = source.codeUnitAt(position);
      } while (CHAR_0 <= char && char <= CHAR_9);
    }
    return _handleLiteral(start, position, isDouble);
  }

  void fail(int position, [String message]) {
    failSpan(new Span(position, position + 20), message);
  }

  void failSpan(Span span, [String message]) {
    if (message == null) message = "Unexpected character";
    listener.fail(source, span, message);
    // If the listener didn't throw, do it here.
    int position = span.start;
    int sliceEnd = span.end;
    String slice;
    if (sliceEnd > source.length) {
      slice = "'${source.substring(position)}'";
    } else {
      slice = "'${source.substring(position, sliceEnd)}...'";
    }
    throw new FormatException("Unexpected character at $position: $slice");
  }
}
