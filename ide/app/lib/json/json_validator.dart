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
  final ErrorSink syntaxErrorSink;
  final List<ContainerEntity> containers = new List<ContainerEntity>();
  final List<StringEntity> keys = new List<StringEntity>();
  final List<JsonEntityValidator> validators = new List<JsonEntityValidator>();
  ContainerEntity currentContainer;
  JsonEntityValidator currentValidator;
  StringEntity key;
  JsonEntity value;

  JsonEntityValidatorListener(this.syntaxErrorSink, this.currentValidator);

  /** Pushes the currently active container (and key, if a [Map]). */
  void pushContainer() {
    if (currentContainer is ObjectEntity) {
      assert(key != null);
      keys.add(key);
    }
    containers.add(currentContainer);
  }

  /** Pops the top container from the [stack], including a key if applicable. */
  void popContainer() {
    value = currentContainer;
    currentContainer = containers.removeLast();
    if (currentContainer is ObjectEntity) {
      key = keys.removeLast();
    }
  }

  void pushValidator() {
    validators.add(currentValidator);
  }

  void popValidator() {
    currentValidator = validators.removeLast();
  }

  void handleString(Span span, String value) {
    this.value = new StringEntity(span, value);
    currentValidator.handleValue(this.value);
  }
  void handleNumber(Span span, num value) {
    this.value = new NumberEntity(span, value);
    currentValidator.handleValue(this.value);
  }
  void handleBool(Span span, bool value) {
    this.value = new BoolEntity(span, value);
    currentValidator.handleValue(this.value);
  }
  void handleNull(Span span) {
    this.value = new NullEntity(span);
    currentValidator.handleValue(this.value);
  }

  // Called when the opening "{" of an object is parsed.
  void beginObject(int position) {
    assert(currentValidator != null);
    pushContainer();
    pushValidator();
    currentContainer = new ObjectEntity();
    currentValidator = currentValidator.enterObject();
  }

  // Called when the closing "}" of an object is parsed.
  void endObject(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ObjectEntity);
    currentContainer.span = span;
    popValidator();
    currentValidator.leaveObject(currentContainer);
    popContainer();
  }

  // Called when the opening "[" of an array is parsed.
  void beginArray(int position) {
    assert(currentValidator != null);
    pushContainer();
    pushValidator();
    currentContainer = new ArrayEntity();
    currentValidator = currentValidator.enterArray();
  }

  // Called when the closing "]" of an array is parsed.
  void endArray(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ArrayEntity);
    currentContainer.span = span;
    popValidator();
    currentValidator.leaveArray(currentContainer);
    popContainer();
  }

  // Called when a ":" is parsed inside an object.
  void propertyName(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ObjectEntity);
    assert(value != null);
    assert(value is StringEntity);
    key = value;
    value = null;
    pushValidator();
    currentValidator = currentValidator.propertyName(key);
  }

  // Called when a "," or "}" is parsed inside an object.
  void propertyValue(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ObjectEntity);
    assert(value != null);
    currentValidator.propertyValue(value);
    popValidator();
    key = value = null;
  }

  // Called when the "," after an array element is parsed.
  // Invariants: current entity is the array element, the parent is an ArrayObject.
  void arrayElement(Span span) {
    assert(currentValidator != null);
    assert(currentContainer != null);
    assert(currentContainer is ArrayEntity);
    assert(value != null);
    currentValidator.arrayElement(value);
    value = null;
  }

  void fail(String source, Span span, String message) {
    syntaxErrorSink.emitMessage(span, message);
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
  // Invoked when any simple value or literal has been parsed.
  void handleValue(ValueEntity entity);

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

  void handleValue(ValueEntity entity) {}

  JsonEntityValidator enterArray() { return instance; }
  void leaveArray(ArrayEntity entity) {}
  void arrayElement(JsonEntity entity) {}

  JsonEntityValidator enterObject() { return instance; }
  void leaveObject(ObjectEntity entity) {}
  JsonEntityValidator propertyName(StringEntity entity) { return instance; }
  void propertyValue(JsonEntity entity) {}
}
