// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.json_validator;

import 'json_parser.dart';

// Abstraction over an error reporting mechanism that understands error
// spans and messages.
abstract class ErrorSink {
  void emitMessage(Span span, String message);
}

class JsonEntityValidatorListener extends JsonListener {
  final ErrorSink _syntaxErrorSink;
  final List<ContainerEntity> _containers = new List<ContainerEntity>();
  final List<StringEntity> _keys = new List<StringEntity>();
  final List<JsonEntityValidator> _validators = new List<JsonEntityValidator>();
  ContainerEntity _currentContainer;
  JsonEntityValidator _currentValidator;
  StringEntity _key;
  JsonEntity _value;

  JsonEntityValidatorListener(this._syntaxErrorSink, this._currentValidator);

  /** Pushes the currently active container (and key, if a [Map]). */
  void pushContainer() {
    if (_currentContainer is ObjectEntity) {
      assert(_key != null);
      _keys.add(_key);
    }
    _containers.add(_currentContainer);
  }

  /** Pops the top container from the [stack], including a key if applicable. */
  void popContainer() {
    _value = _currentContainer;
    _currentContainer = _containers.removeLast();
    if (_currentContainer is ObjectEntity) {
      _key = _keys.removeLast();
    }
  }

  void pushValidator() {
    _validators.add(_currentValidator);
  }

  void popValidator() {
    _currentValidator = _validators.removeLast();
  }

  void handleString(Span span, String value) {
    _value = new StringEntity(span, value);
  }

  void handleNumber(Span span, num value) {
    _value = new NumberEntity(span, value);
  }

  void handleBool(Span span, bool value) {
    _value = new BoolEntity(span, value);
  }

  void handleNull(Span span) {
    _value = new NullEntity(span);
  }

  // Called when the opening "{" of an object is parsed.
  void beginObject(int position) {
    assert(_currentValidator != null);
    pushContainer();
    pushValidator();
    _currentContainer = new ObjectEntity();
    _currentValidator = _currentValidator.enterObject();
  }

  // Called when the closing "}" of an object is parsed.
  void endObject(Span span) {
    assert(_currentValidator != null);
    assert(_currentContainer != null);
    assert(_currentContainer is ObjectEntity);
    _currentContainer.span = span;
    popValidator();
    _currentValidator.leaveObject(_currentContainer);
    popContainer();
  }

  // Called when the opening "[" of an array is parsed.
  void beginArray(int position) {
    assert(_currentValidator != null);
    pushContainer();
    pushValidator();
    _currentContainer = new ArrayEntity();
    _currentValidator = _currentValidator.enterArray();
  }

  // Called when the closing "]" of an array is parsed.
  void endArray(Span span) {
    assert(_currentValidator != null);
    assert(_currentContainer != null);
    assert(_currentContainer is ArrayEntity);
    _currentContainer.span = span;
    popValidator();
    _currentValidator.leaveArray(_currentContainer);
    popContainer();
  }

  // Called when a ":" is parsed inside an object.
  void propertyName(Span span) {
    assert(_currentValidator != null);
    assert(_currentContainer != null);
    assert(_currentContainer is ObjectEntity);
    assert(_value != null);
    assert(_value is StringEntity);
    _key = _value;
    _value = null;
    pushValidator();
    _currentValidator = _currentValidator.propertyName(_key);
  }

  // Called when a "," or "}" is parsed inside an object.
  void propertyValue(Span span) {
    assert(_currentValidator != null);
    assert(_currentContainer != null);
    assert(_currentContainer is ObjectEntity);
    assert(_value != null);
    _currentValidator.propertyValue(_value);
    popValidator();
    _key = _value = null;
  }

  // Called when the "," after an array element is parsed.
  // Invariants: current entity is the array element, the parent is an ArrayObject.
  void arrayElement(Span span) {
    assert(_currentValidator != null);
    assert(_currentContainer != null);
    assert(_currentContainer is ArrayEntity);
    assert(_value != null);
    _currentValidator.arrayElement(_value);
    _value = null;
  }

  void endDocument(Span span) {
    if (_value is ValueEntity) {
      _currentValidator.handleRootValue(_value);
    }
  }

  void fail(String source, Span span, String message) {
    _syntaxErrorSink.emitMessage(span, message);
  }
}

// Abstract base class of all types of json entities that are parsed
// and exposed with a [Span].
abstract class JsonEntity {
  Span span;
}

// Abstract base class for simple values.
abstract class ValueEntity extends JsonEntity {
  get value;
}

// Abstract base class for containers (array and object).
abstract class ContainerEntity extends JsonEntity {
}

// Entity for string values.
class StringEntity extends ValueEntity {
  String text;
  StringEntity(Span span, this.text) {
    this.span = span;
  }

  get value => this.text;
}

// Entity for "null" literal values.
class NullEntity extends ValueEntity {
  NullEntity(Span span) {
    this.span = span;
  }

  get value => null;
}

// Entity for numeric values.
class NumberEntity extends ValueEntity {
  num number;
  NumberEntity(Span span, this.number) {
    this.span = span;
  }

  get value => this.number;
}

// Entity for "true" or "false" literal values.
class BoolEntity extends ValueEntity {
  bool boolValue;
  BoolEntity(Span span, this.boolValue) {
    this.span = span;
  }

  get value => this.boolValue;
}

// Entity for array values.
class ArrayEntity extends ContainerEntity {
}

// Entity for object values.
class ObjectEntity extends ContainerEntity {
}

// Event based interface of a json validator.
abstract class JsonEntityValidator {
  // Invoked when the json document contains a single root literal value.
  void handleRootValue(ValueEntity entity);

  // Invoked when entering an array
  JsonEntityValidator enterArray();
  // Invoked when leaving an array
  void leaveArray(ArrayEntity entity);
  // Invoked after parsing an array value
  void arrayElement(JsonEntity entity);

  // Invoked when entering an object
  JsonEntityValidator enterObject();
  // Invoked when leaving an object
  void leaveObject(ObjectEntity entity);
  // Invoked after parsing an property name inside an object
  JsonEntityValidator propertyName(StringEntity entity);
  // Invoked after parsing a propery value inside an object
  void propertyValue(JsonEntity entity);
}

// No-op base implementation of a [Validator].
class NullValidator implements JsonEntityValidator {
  static final JsonEntityValidator instance = new NullValidator();

  void handleRootValue(ValueEntity entity) {}

  JsonEntityValidator enterArray() { return instance; }
  void leaveArray(ArrayEntity entity) {}
  void arrayElement(JsonEntity entity) {}

  JsonEntityValidator enterObject() { return instance; }
  void leaveObject(ObjectEntity entity) {}
  JsonEntityValidator propertyName(StringEntity entity) { return instance; }
  void propertyValue(JsonEntity entity) {}
}
