// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.jason_validator_test;

import 'package:unittest/unittest.dart';
import '../lib/json/json_parser.dart';
import '../lib/json/json_validator.dart';
import '../lib/json/utils.dart';

class _ValidatorEvent {
  static const int ROOT_VALUE = 1;
  static const int ENTER_OBJECT = 2;
  static const int LEAVE_OBJECT = 3;
  static const int PROPERTY_NAME = 4;
  static const int PROPERTY_VALUE = 5;
  static const int ENTER_ARRAY = 6;
  static const int LEAVE_ARRAY = 7;
  static const int ARRAY_ELEMENT = 8;

  final int validatorId;
  final int kind;
  final Span span;
  final value;
  final LineColumn startLineColumn;
  final LineColumn endLineColumn;

  _ValidatorEvent(this.validatorId, this.kind, this.span, this.value, this.startLineColumn, this.endLineColumn);
}

abstract class _LoggingValidatorBase implements JsonEntityValidator {
  void _addEvent(int kind, [Span span, var value]) {
    LineColumn startLineColumn;
    LineColumn endLineColumn;
    if (span != null) {
      startLineColumn = lineOffsets.getLineColumn(span.start);
      endLineColumn = lineOffsets.getLineColumn(span.end);
    }
    events.add(new _ValidatorEvent(id, kind, span, value, startLineColumn, endLineColumn));
  }

  void handleRootValue(ValueEntity entity) {
    _addEvent(_ValidatorEvent.ROOT_VALUE, entity.span, entity.value);
  }

  JsonEntityValidator enterArray() {
    _addEvent(_ValidatorEvent.ENTER_ARRAY);
    return createChildValidator(this);
  }

  void leaveArray(ArrayEntity entity) {
    _addEvent(_ValidatorEvent.LEAVE_ARRAY, entity.span);
  }

  void arrayElement(JsonEntity entity) {
    var value = (entity is ValueEntity ? entity.value : null);
    _addEvent(_ValidatorEvent.ARRAY_ELEMENT, entity.span, value);
  }

  JsonEntityValidator enterObject() {
    _addEvent(_ValidatorEvent.ENTER_OBJECT);
    return createChildValidator(this);
  }

  void leaveObject(ObjectEntity entity) {
    _addEvent(_ValidatorEvent.LEAVE_OBJECT, entity.span);
  }

  JsonEntityValidator propertyName(StringEntity entity) {
    _addEvent(_ValidatorEvent.PROPERTY_NAME, entity.span, entity.text);
    return createChildValidator(this);
  }

  void propertyValue(JsonEntity entity) {
    var value = (entity is ValueEntity ? entity.value : null);
    _addEvent(_ValidatorEvent.PROPERTY_VALUE, entity.span, value);
  }

  StringLineOffsets get lineOffsets;
  List<_ValidatorEvent> get events;
  int get id;
  JsonEntityValidator createChildValidator(JsonEntityValidator parent);
}

/**
 * The logging validator used at the top of the json document.
 */
class _LoggingValidator extends _LoggingValidatorBase {
  final String contents;
  final List<_ValidatorEvent> events = new List();
  final int id;
  final StringLineOffsets lineOffsets;
  int currentId;

  _LoggingValidator(String contents)
    : this.contents = contents,
      this.id = 0,
      this.lineOffsets = new StringLineOffsets(contents) {
    currentId = 0;
  }

  JsonEntityValidator createChildValidator(JsonEntityValidator parent) {
    currentId++;
    return new _ChildLoggingValidator(this, parent, currentId);
  }
}

/**
 * The logging validator used when traversing json containers.
 */
class _ChildLoggingValidator extends _LoggingValidatorBase {
  final _LoggingValidator root;
  final JsonEntityValidator parent;
  final int id;

  _ChildLoggingValidator(this.root, this.parent, this.id);

  JsonEntityValidator createChildValidator(JsonEntityValidator parent) {
    return root.createChildValidator(parent);
  }

  List<_ValidatorEvent> get events => root.events;
  StringLineOffsets get lineOffsets => root.lineOffsets;
}

class _ErrorEvent {
  final Span span;
  final String message;

  _ErrorEvent(this.span, this.message);
}

class _LoggingErrorSink implements ErrorSink {
  final List<_ErrorEvent> events = new List<_ErrorEvent>();
  void emitMessage(Span span, String message) {
    _ErrorEvent event = new _ErrorEvent(span, message);
    events.add(event);
  }
}

void defineTests() {
  void expectEvent(_LoggingValidator validator, int eventIndex, int validatorId, int kind, [int startLine, int startColumn, int endLine, int endColumn, var value]) {
    expect(eventIndex, lessThan(validator.events.length));
    _ValidatorEvent event = validator.events[eventIndex];
    if (value == null) {
      value = event.value;
    }
    expect(event.validatorId, equals(validatorId));
    expect(event.kind, equals(kind));
    if (startLine != null)
      expect(event.startLineColumn.line, equals(startLine));
    if (startColumn != null)
      expect(event.startLineColumn.column, equals(startColumn));
    if (endLine != null)
      expect(event.endLineColumn.line, equals(endLine));
    if (endColumn != null)
      expect(event.endLineColumn.column, equals(endColumn));
    expect(event.value, equals(value));
  }

  void expectValue(_LoggingValidator validator, int eventIndex, int validatorId, int kind, var value) {
    expectEvent(validator, eventIndex, validatorId, kind, null, null, null, null, value);
  }
  void expectEventEnd(_LoggingValidator validator, int eventIndex) {
    expect(eventIndex, equals(validator.events.length));
  }

  _LoggingValidator validateDocument(String contents) {
    _LoggingErrorSink errorSink = new _LoggingErrorSink();
    _LoggingValidator validator = new _LoggingValidator(contents);
    JsonEntityValidatorListener listener = new JsonEntityValidatorListener(errorSink, validator);
    JsonParser parser = new JsonParser(contents, listener);
    parser.parse();
    return validator;
  }

  group('Json validator tests -', () {
    test('empty object', () {
      String contents = """
{
}
""";
      _LoggingValidator validator = validateDocument(contents);
      int eventIndex = 0;
      expectEvent(validator, eventIndex++, 0, _ValidatorEvent.ENTER_OBJECT);
      expectEvent(validator, eventIndex++, 0, _ValidatorEvent.LEAVE_OBJECT, 1, 1, 2, 2);
      expectEventEnd(validator, eventIndex++);
    });

    test('empty array', () {
      String contents = """
[
]
""";
      _LoggingValidator validator = validateDocument(contents);
      int eventIndex = 0;
      expectEvent(validator, eventIndex++, 0, _ValidatorEvent.ENTER_ARRAY);
      expectEvent(validator, eventIndex++, 0, _ValidatorEvent.LEAVE_ARRAY, 1, 1, 2, 2);
      expectEventEnd(validator, eventIndex++);
    });

    test('single root value', () {
      String contents = """
123456
""";
      _LoggingValidator validator = validateDocument(contents);
      int eventIndex = 0;
      expectEvent(validator, eventIndex++, 0, _ValidatorEvent.ROOT_VALUE, 1, 1, 1, 7, 123456);
      expectEventEnd(validator, eventIndex++);
    });

    test('object containing single property and value', () {
      String contents = """
{
  "foo": true
}
""";
      _LoggingValidator validator = validateDocument(contents);
      int eventIndex = 0;
      expectEvent(validator, eventIndex++, 0, _ValidatorEvent.ENTER_OBJECT);
      expectEvent(validator, eventIndex++, 1, _ValidatorEvent.PROPERTY_NAME, 2, 3, 2, 8, "foo");
      expectEvent(validator, eventIndex++, 2, _ValidatorEvent.PROPERTY_VALUE, 2, 10, 2, 14, true);
      expectEvent(validator, eventIndex++, 0, _ValidatorEvent.LEAVE_OBJECT, 1, 1, 3, 2);
      expectEventEnd(validator, eventIndex++);
    });

    test('object containing an array and an object property', () {
      String contents = """
{
  "foo": [1, "foo"],
  "bar": { "blah": false, "test": 1 }
}
""";
      _LoggingValidator validator = validateDocument(contents);
      int eventIndex = 0;
      expectEvent(validator, eventIndex++, 0, _ValidatorEvent.ENTER_OBJECT);
      expectValue(validator, eventIndex++, 1, _ValidatorEvent.PROPERTY_NAME, "foo");
      expectEvent(validator, eventIndex++, 2, _ValidatorEvent.ENTER_ARRAY);
      expectValue(validator, eventIndex++, 3, _ValidatorEvent.ARRAY_ELEMENT, 1);
      expectValue(validator, eventIndex++, 3, _ValidatorEvent.ARRAY_ELEMENT, "foo");
      expectEvent(validator, eventIndex++, 2, _ValidatorEvent.LEAVE_ARRAY);
      expectEvent(validator, eventIndex++, 2, _ValidatorEvent.PROPERTY_VALUE);
      expectValue(validator, eventIndex++, 1, _ValidatorEvent.PROPERTY_NAME, "bar");
      expectEvent(validator, eventIndex++, 4, _ValidatorEvent.ENTER_OBJECT);
      expectValue(validator, eventIndex++, 5, _ValidatorEvent.PROPERTY_NAME, "blah");
      expectValue(validator, eventIndex++, 6, _ValidatorEvent.PROPERTY_VALUE, false);
      expectValue(validator, eventIndex++, 5, _ValidatorEvent.PROPERTY_NAME, "test");
      expectValue(validator, eventIndex++, 7, _ValidatorEvent.PROPERTY_VALUE, 1);
      expectEvent(validator, eventIndex++, 4, _ValidatorEvent.LEAVE_OBJECT);
      expectEvent(validator, eventIndex++, 4, _ValidatorEvent.PROPERTY_VALUE, 3, 10, 3, 38);
      expectEvent(validator, eventIndex++, 0, _ValidatorEvent.LEAVE_OBJECT, 1, 1, 4, 2);
      expectEventEnd(validator, eventIndex++);
    });
  });
}
