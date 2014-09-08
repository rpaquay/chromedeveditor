// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test.services.refactoring.extract_method;

import 'dart:async';

import 'package:analysis_server/src/protocol.dart';
import 'package:analysis_server/src/services/refactoring/extract_method.dart';
import 'package:analysis_server/src/services/refactoring/refactoring.dart';
import '../../reflective_tests.dart';
import 'package:unittest/unittest.dart';

import 'abstract_refactoring.dart';


main() {
  groupSep = ' | ';
  runReflectiveTests(ExtractMethodTest);
}


@ReflectiveTestCase()
class ExtractMethodTest extends RefactoringTest {
  ExtractMethodRefactoringImpl refactoring;

  test_bad_assignmentLeftHandSide() {
    indexTestUnit('''
main() {
  int aaa;
  aaa = 0;
}
''');
    _createRefactoringForString('aaa ');
    return _assertConditionsFatal(
        'Cannot extract the left-hand side of an assignment.');
  }

  test_bad_comment_selectionEndsInside() {
    indexTestUnit('''
main() {
// start
  print(0);
/*
// end
*/
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal('Selection ends inside a comment.');
  }

  test_bad_comment_selectionStartsInside() {
    indexTestUnit('''
main() {
/*
// start
*/
  print(0);
// end
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal('Selection begins inside a comment.');
  }

  test_bad_conflict_method_alreadyDeclaresMethod() {
    indexTestUnit('''
class A {
  void res() {}
  main() {
// start
    print(0);
// end
  }
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsError(
        "Class 'A' already declares method with name 'res'.");
  }

  test_bad_conflict_method_shadowsSuperDeclaration() {
    indexTestUnit('''
class A {
  void res() {} // marker
}
class B extends A {
  main() {
    res();
// start
    print(0);
// end
  }
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsError("Created method will shadow method 'A.res'.");
  }

  test_bad_conflict_topLevel_alreadyDeclaresFunction() {
    indexTestUnit('''
library my.lib;

void res() {}
main() {
// start
  print(0);
// end
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsError(
        "Library already declares function with name 'res'.");
  }

  test_bad_conflict_topLevel_willHideInheritedMemberUsage() {
    indexTestUnit('''
class A {
  void res() {}
}
class B extends A {
  foo() {
    res(); // marker
  }
}
main() {
// start
  print(0);
// end
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsError(
        "Created function will shadow method 'A.res'.");
  }

  test_bad_constructor_initializer() {
    indexTestUnit('''
class A {
  int f;
  A() : f = 0 {}
}
''');
    _createRefactoringForString('f = 0');
    return _assertConditionsFatal(
        'Cannot extract a constructor initializer. Select expression part of initializer.');
  }

  test_bad_constructor_redirectingConstructor() {
    indexTestUnit('''
class A {
  A() : this.named();
  A.named() {}
}
''');
    _createRefactoringForString('this.named()');
    return _assertConditionsFatal(
        'Cannot extract a constructor initializer. Select expression part of initializer.');
  }

  test_bad_constructor_superConstructor() {
    indexTestUnit('''
class A {}
class B extends A {
  B() : super();
}
''');
    _createRefactoringForString('super()');
    return _assertConditionsFatal(
        'Cannot extract a constructor initializer. Select expression part of initializer.');
  }

  test_bad_doWhile_body() {
    indexTestUnit('''
main() {
  do 
// start
  { 
  }
// end
  while (true);
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Operation not applicable to a 'do' statement's body and expression.");
  }

  test_bad_emptySelection() {
    indexTestUnit('''
main() {
// start
// end
  print(0);
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Can only extract a single expression or a set of statements.");
  }

  test_bad_forLoop_conditionAndUpdaters() {
    indexTestUnit('''
main() {
  for ( 
    int i = 0;
// start
    i < 10; 
    i++
// end
  ) {}
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Operation not applicable to a 'for' statement's condition and updaters.");
  }

  test_bad_forLoop_init() {
    indexTestUnit('''
main() {
  for ( 
// start
    int i = 0
// end
    ; i < 10;
    i++
  ) {}
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Cannot extract initialization part of a 'for' statement.");
  }

  test_bad_forLoop_initAndCondition() {
    indexTestUnit('''
main() {
  for ( 
// start
    int i = 0;
    i < 10;
// end
    i++
  ) {}
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Operation not applicable to a 'for' statement's initializer and condition.");
  }

  test_bad_forLoop_updaters() {
    indexTestUnit('''
main() {
  for ( 
    int i = 0;
    i < 10;
// start
    i++
// end
  ) {}
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Cannot extract increment part of a 'for' statement.");
  }

  test_bad_forLoop_updatersAndBody() {
    indexTestUnit('''
main() {
  for ( 
    int i = 0;
    i < 10;
// start
    i++
  ) {}
// end
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Operation not applicable to a 'for' statement's updaters and body.");
  }

  test_bad_methodName_reference() {
    indexTestUnit('''
main() {
  main();
}
''');
    _createRefactoringWithSuffix('main', '();');
    return _assertConditionsFatal("Cannot extract a single method name.");
  }

  test_bad_namePartOfDeclaration_function() {
    indexTestUnit('''
main() {
}
''');
    _createRefactoringForString('main');
    return _assertConditionsFatal(
        "Cannot extract the name part of a declaration.");
  }

  test_bad_namePartOfDeclaration_variable() {
    indexTestUnit('''
main() {
  int vvv = 0;
}
''');
    _createRefactoringForString('vvv');
    return _assertConditionsFatal(
        "Cannot extract the name part of a declaration.");
  }

  test_bad_namePartOfQualified() {
    indexTestUnit('''
class A {
  var fff;
}
main() {
  A a;
  a.fff = 1;
}
''');
    _createRefactoringWithSuffix('fff', ' = 1');
    return _assertConditionsFatal(
        "Can not extract name part of a property access.");
  }

  test_bad_newMethodName_notIdentifier() {
    indexTestUnit('''
main() {
// start
  print(0);
// end
}
''');
    _createRefactoringForStartEndComments();
    refactoring.name = 'bad-name';
    // check conditions
    return _assertConditionsError("Method name must not contain '-'.");
  }

  test_bad_notSameParent() {
    indexTestUnit('''
main() {
  while (false) 
// start
  { 
  } 
  print(0);
// end
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        'Not all selected statements are enclosed by the same parent statement.');
  }

  test_bad_parameterName_duplicate() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
// start
  int a = v1 + v2; // marker
// end
}
''');
    _createRefactoringForStartEndComments();
    // update parameters
    return refactoring.checkInitialConditions().then((_) {
      {
        var parameters = _getParametersCopy();
        expect(parameters, hasLength(2));
        parameters[0].name = 'dup';
        parameters[1].name = 'dup';
        refactoring.parameters = parameters;
      }
      return _assertFinalConditionsError("Parameter 'dup' already exists");
    });
  }

  test_bad_parameterName_inUse() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
// start
  int a = v1 + v2; // marker
// end
}
''');
    _createRefactoringForStartEndComments();
    // update parameters
    return refactoring.checkInitialConditions().then((_) {
      {
        var parameters = _getParametersCopy();
        expect(parameters, hasLength(2));
        parameters[0].name = 'a';
        refactoring.parameters = parameters;
      }
      return _assertFinalConditionsError(
          "'a' is already used as a name in the selected code");
    });
  }

  test_bad_selectionEndsInSomeNode() {
    indexTestUnit('''
main() {
// start
  print(0);
  print(1);
// end
}
''');
    _createRefactoringForStartEndString('print(0', 'rint(1)');
    return _assertConditionsFatal(
        "The selection does not cover a set of statements or an expression. "
            "Extend selection to a valid range.");
  }

  test_bad_statements_return_andAssignsVariable() {
    indexTestUnit('''
main() {
// start
  var v = 0;
  return 42;
// end
  print(v);
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Ambiguous return value: Selected block contains assignment(s) to "
            "local variables and return statement.");
  }

  test_bad_switchCase() {
    indexTestUnit('''
main() {
  switch (1) { 
// start
    case 0: break;
// end
  }
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Selection must either cover whole switch statement "
            "or parts of a single case block.");
  }

  test_bad_tokensBetweenLastNodeAndSelectionEnd() {
    indexTestUnit('''
main() {
// start
  print(0);
  print(1);
}
// end
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "The end of the selection contains characters that do not belong to a statement.");
  }

  test_bad_tokensBetweenSelectionStartAndFirstNode() {
    indexTestUnit('''
main() {
// start
  print(0); // marker
  print(1);
// end
}
''');
    _createRefactoringForStartEndString('); // marker', '// end');
    return _assertConditionsFatal(
        "The beginning of the selection contains characters that do not belong to a statement.");
  }

  test_bad_try_catchBlock_block() {
    indexTestUnit('''
main() {
  try
  {} 
  catch (e)
// start
  {}
// end
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Selection must either cover whole try statement or "
            "parts of try, catch, or finally block.");
  }

  test_bad_try_catchBlock_complete() {
    indexTestUnit('''
main() {
  try
  {} 
// start
  catch (e)
  {}
// end
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Selection must either cover whole try statement or "
            "parts of try, catch, or finally block.");
  }

  test_bad_try_catchBlock_exception() {
    indexTestUnit('''
main() {
  try {
  } catch ( 
// start
  e
// end
  ) {
  }
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        'Cannot extract the name part of a declaration.');
  }

  test_bad_try_finallyBlock() {
    indexTestUnit('''
main() {
  try
  {} 
  finally
// start
  {}
// end
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Selection must either cover whole try statement or "
            "parts of try, catch, or finally block.");
  }

  test_bad_try_tryBlock() {
    indexTestUnit('''
main() {
  try
// start
  {} 
// end
  finally
  {}
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Selection must either cover whole try statement or "
            "parts of try, catch, or finally block.");
  }

  test_bad_typeReference() {
    indexTestUnit('''
main() {
  int a = 0;
}
''');
    _createRefactoringForString("int");
    return _assertConditionsFatal("Cannot extract a single type reference.");
  }

  test_bad_variableDeclarationFragment() {
    indexTestUnit('''
main() {
  int 
// start
    a = 1
// end
    ,b = 2;
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Cannot extract a variable declaration fragment. Select whole declaration statement.");
  }

  test_bad_while_conditionAndBody() {
    indexTestUnit('''
main() {
  while 
// start
    (false) 
  { 
  } 
// end
}
''');
    _createRefactoringForStartEndComments();
    return _assertConditionsFatal(
        "Operation not applicable to a while statement's expression and body.");
  }

  test_canExtractGetter_false_fieldAssignment() {
    indexTestUnit('''
class A {
  var f;
  main() {
// start
    f = 1;
// end
  }
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.canCreateGetter, false);
      expect(refactoring.createGetter, false);
    });
  }

  test_canExtractGetter_false_hasParameters() {
    indexTestUnit('''
main(int p) {
  int a = p + 1;
}
''');
    _createRefactoringForString('p + 1');
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.canCreateGetter, false);
      expect(refactoring.createGetter, false);
    });
  }

  test_canExtractGetter_false_returnNotUsed_assignment() {
    indexTestUnit('''
var topVar = 0;
f(int p) {
  topVar = 5;
}
''');
    _createRefactoringForString('topVar = 5');
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.canCreateGetter, false);
      expect(refactoring.createGetter, false);
    });
  }

  test_canExtractGetter_false_returnNotUsed_noReturn() {
    indexTestUnit('''
var topVar = 0;
main() {
// start
  int a = 1;
  int b = 2;
  topVar = a + b;
// end
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.canCreateGetter, false);
      expect(refactoring.createGetter, false);
    });
  }

  test_canExtractGetter_true() {
    indexTestUnit('''
main() {
  int a = 1 + 2;
}
''');
    _createRefactoringForString('1 + 2');
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.canCreateGetter, true);
      expect(refactoring.createGetter, true);
    });
  }

  test_checkName() {
    indexTestUnit('''
main() {
  int a = 1 + 2;
}
''');
    _createRefactoringForString('1 + 2');
    // null
    refactoring.name = null;
    assertRefactoringStatus(
        refactoring.checkName(),
        RefactoringProblemSeverity.FATAL,
        expectedMessage: "Method name must not be null.");
    // empty
    refactoring.name = '';
    assertRefactoringStatus(
        refactoring.checkName(),
        RefactoringProblemSeverity.FATAL,
        expectedMessage: "Method name must not be empty.");
    // OK
    refactoring.name = 'res';
    assertRefactoringStatusOK(refactoring.checkName());
  }

  test_closure_asFunction_singleExpression() {
    indexTestUnit('''
process(f(x)) {}
main() {
  process((x) => x * 2);
}
''');
    _createRefactoringForString('(x) => x * 2');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
process(f(x)) {}
main() {
  process(res);
}

res(x) => x * 2;
''');
  }

  test_closure_asFunction_statements() {
    indexTestUnit('''
process(f(x)) {}
main() {
  process((x) {
    print(x);
    return x * 2;
  }); // marker
}
''');
    _createRefactoringForStartEndString('(x) {', '); // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
process(f(x)) {}
main() {
  process(res); // marker
}

res(x) {
  print(x);
  return x * 2;
}
''');
  }

  test_closure_asMethod_statements() {
    indexTestUnit('''
process(f(x)) {}
class A {
  int k = 2;
  main() {
    process((x) {
      print(x);
      return x * k;
    }); // marker
  }
}
''');
    _createRefactoringForStartEndString('(x) {', '); // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
process(f(x)) {}
class A {
  int k = 2;
  main() {
    process(res); // marker
  }

  res(x) {
    print(x);
    return x * k;
  }
}
''');
  }

  test_closure_bad_referencesLocalVariable() {
    indexTestUnit('''
process(f(x)) {}
main() {
  int k = 2;
  process((x) => x * k);
}
''');
    _createRefactoringForString('(x) => x * k');
    // check
    return refactoring.checkInitialConditions().then((status) {
      assertRefactoringStatus(
          status,
          RefactoringProblemSeverity.FATAL,
          expectedMessage:
              'Cannot extract closure as method, it references 1 external variable(s).');
    });
  }

  test_closure_bad_referencesParameter() {
    indexTestUnit('''
process(f(x)) {}
main(int k) {
  process((x) => x * k);
}
''');
    _createRefactoringForString('(x) => x * k');
    // check
    return refactoring.checkInitialConditions().then((status) {
      assertRefactoringStatus(
          status,
          RefactoringProblemSeverity.FATAL,
          expectedMessage:
              'Cannot extract closure as method, it references 1 external variable(s).');
    });
  }

  test_fromTopLevelVariableInitializerClosure() {
    indexTestUnit('''
var X = 1;

var Y = () {
  return 1 + X;
};
''');
    _createRefactoringForString('1 + X');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
var X = 1;

var Y = () {
  return res();
};

num res() => 1 + X;
''');
  }

  test_getExtractGetter_false_do() {
    indexTestUnit('''
main() {
// start
  int v = 0;
  do {
    v++;
  } while (v < 10);
// end
  print(v);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.createGetter, false);
    });
  }

  test_getExtractGetter_false_for() {
    indexTestUnit('''
main() {
// start
  int v = 0;
  for (int i = 0; i < 10; i++) {
    v += i;
  }
// end
  print(v);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.createGetter, false);
    });
  }

  test_getExtractGetter_false_forEach() {
    indexTestUnit('''
main() {
// start
  int v = 0;
  for (int i in [1, 2, 3]) {
    v += i;
  }
// end
  print(v);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.createGetter, false);
    });
  }

  test_getExtractGetter_false_methodInvocation_expression() {
    indexTestUnit('''
main() {
  int v = calculateSomething() + 5;
}
int calculateSomething() => 42;
''');
    _createRefactoringForString('calculateSomething() + 5');
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.createGetter, false);
    });
  }

  test_getExtractGetter_false_methodInvocation_statements() {
    indexTestUnit('''
main() {
// start
  int v = calculateSomething();
// end
  print(v);
}
int calculateSomething() => 42;
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.createGetter, false);
    });
  }

  test_getExtractGetter_false_while() {
    indexTestUnit('''
main() {
// start
  int v = 0;
  while (v < 10) {
    v++;
  }
// end
  print(v);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.createGetter, false);
    });
  }

  test_getExtractGetter_true_simpleBlock() {
    indexTestUnit('''
main() {
// start
  int v = 1 + 2;
// end
  print(v);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.createGetter, true);
    });
  }

  test_getExtractGetter_true_singleExpression() {
    indexTestUnit('''
main() {
// start
  int v = 1 + 2;
// end
  print(v);
}
''');
    _createRefactoringForString('1 + 2');
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.createGetter, true);
    });
  }

  test_getRefactoringName_function() {
    indexTestUnit('''
main() {
  print(1 + 2);
}
''');
    _createRefactoringForString('1 + 2');
    expect(refactoring.refactoringName, 'Extract Function');
  }

  test_getRefactoringName_method() {
    indexTestUnit('''
class A {
  main() {
    print(1 + 2);
  }
}
''');
    _createRefactoringForString('1 + 2');
    expect(refactoring.refactoringName, 'Extract Method');
  }

  test_names_singleExpression() {
    indexTestUnit('''
class TreeItem {}
TreeItem getSelectedItem() => null;
process(my) {}
main() {
  process(getSelectedItem()); // marker
  int treeItem = 0;
}
''');
    _createRefactoringWithSuffix('getSelectedItem()', '); // marker');
    // check names
    return refactoring.checkInitialConditions().then((_) {
      expect(
          refactoring.names,
          unorderedEquals(['selectedItem', 'item', 'my', 'treeItem2']));
    });
  }

  test_offsets_lengths() {
    indexTestUnit('''
main() {
  int a = 1 + 2;
  int b = 1 +  2;
}
''');
    _createRefactoringForString('1 +  2');
    // apply refactoring
    return refactoring.checkInitialConditions().then((_) {
      expect(
          refactoring.offsets,
          unorderedEquals([findOffset('1 + 2'), findOffset('1 +  2')]));
      expect(refactoring.lengths, unorderedEquals([5, 6]));
    });
  }

  test_returnType_expression() {
    indexTestUnit('''
main() {
  int a = 1 + 2;
}
''');
    _createRefactoringForString('1 + 2');
    // do check
    return refactoring.checkInitialConditions().then((_) {
      expect(refactoring.returnType, 'int');
    });
  }

  test_returnType_statements() {
    indexTestUnit('''
main() {
// start
  double v = 5.0;
// end
  print(v);
}
''');
    _createRefactoringForStartEndComments();
    // do check
    return refactoring.checkInitialConditions().then((_) {
      expect(refactoring.returnType, 'double');
    });
  }

  test_returnType_statements_void() {
    indexTestUnit('''
main() {
// start
  print(42);
// end
}
''');
    _createRefactoringForStartEndComments();
    // do check
    return refactoring.checkInitialConditions().then((_) {
      expect(refactoring.returnType, 'void');
    });
  }

  test_setExtractGetter() {
    indexTestUnit('''
main() {
  int a = 1 + 2;
}
''');
    _createRefactoringForString('1 + 2');
    // apply refactoring
    return assertRefactoringConditionsOK().then((_) {
      expect(refactoring.canCreateGetter, true);
      expect(refactoring.createGetter, true);
      return refactoring.createChange().then((SourceChange refactoringChange) {
        this.refactoringChange = refactoringChange;
        assertTestChangeResult('''
main() {
  int a = res;
}

int get res => 1 + 2;
''');
      });
    });
  }

  test_singleExpression() {
    indexTestUnit('''
main() {
  int a = 1 + 2;
}
''');
    _createRefactoringForString('1 + 2');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  int a = res();
}

int res() => 1 + 2;
''');
  }

  test_singleExpression_cascade() {
    indexTestUnit('''
main() {
  String s = '';
  var v = s..length;
}
''');
    _createRefactoringForString('s..length');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  String s = '';
  var v = res(s);
}

String res(String s) => s..length;
''');
  }

  test_singleExpression_dynamic() {
    indexTestUnit('''
dynaFunction() {}
main() {
  var v = dynaFunction(); // marker
}
''');
    _createRefactoringWithSuffix('dynaFunction()', '; // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
dynaFunction() {}
main() {
  var v = res(); // marker
}

res() => dynaFunction();
''');
  }

  test_singleExpression_ignore_assignmentLeftHandSize() {
    indexTestUnit('''
main() {
  getButton().text = 'txt';
  print(getButton().text); // marker
}
getButton() {}
''');
    _createRefactoringWithSuffix('getButton().text', '); // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  getButton().text = 'txt';
  print(res()); // marker
}

res() => getButton().text;
getButton() {}
''');
  }

  test_singleExpression_occurrences() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int positiveA = v1 + v2; // marker
  int positiveB = v2 + v3;
  int positiveC = v1 +  v2;
  int positiveD = v1/*abc*/ + v2;
  int negA = 1 + 2;
  int negB = 1 + v2;
  int negC = v1 + 2;
  int negD = v1 * v2;
}
''');
    _createRefactoringWithSuffix('v1 + v2', '; // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int positiveA = res(v1, v2); // marker
  int positiveB = res(v2, v3);
  int positiveC = res(v1, v2);
  int positiveD = res(v1, v2);
  int negA = 1 + 2;
  int negB = 1 + v2;
  int negC = v1 + 2;
  int negD = v1 * v2;
}

int res(int v1, int v2) => v1 + v2;
''');
  }

  test_singleExpression_occurrences_disabled() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int a = v1 + v2; // marker
  int b = v2 + v3;
}
''');
    _createRefactoringWithSuffix('v1 + v2', '; // marker');
    refactoring.extractAll = false;
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int a = res(v1, v2); // marker
  int b = v2 + v3;
}

int res(int v1, int v2) => v1 + v2;
''');
  }

  test_singleExpression_occurrences_inClassOnly() {
    indexTestUnit('''
class A {
  myMethod() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = v1 + v2; // marker
  }
}
main() {
  int v1 = 1;
  int v2 = 2;
  int negA = v1 + v2;
}
''');
    _createRefactoringWithSuffix('v1 + v2', '; // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
class A {
  myMethod() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = res(v1, v2); // marker
  }

  int res(int v1, int v2) => v1 + v2;
}
main() {
  int v1 = 1;
  int v2 = 2;
  int negA = v1 + v2;
}
''');
  }

  test_singleExpression_occurrences_inWholeUnit() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
  int positiveA = v1 + v2; // marker
}
class A {
  myMethod() {
    int v1 = 1;
    int v2 = 2;
    int positiveB = v1 + v2;
  }
}
''');
    _createRefactoringWithSuffix('v1 + v2', '; // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  int v1 = 1;
  int v2 = 2;
  int positiveA = res(v1, v2); // marker
}

int res(int v1, int v2) => v1 + v2;
class A {
  myMethod() {
    int v1 = 1;
    int v2 = 2;
    int positiveB = res(v1, v2);
  }
}
''');
  }

  test_singleExpression_returnTypeGeneric() {
    indexTestUnit('''
main() {
  var v = new List<String>();
}
''');
    _createRefactoringForString('new List<String>()');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  var v = res();
}

List<String> res() => new List<String>();
''');
  }

  test_singleExpression_returnTypePrefix() {
    indexTestUnit('''
import 'dart:math' as pref;
main() {
  var v = new pref.Random();
}
''');
    _createRefactoringForString('new pref.Random()');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
import 'dart:math' as pref;
main() {
  var v = res();
}

pref.Random res() => new pref.Random();
''');
  }

  test_singleExpression_staticContext_extractFromInitializer() {
    indexTestUnit('''
class A {
  A(int v) {}
}
class B extends A {
  B() : super(1 + 2) {}
}
''');
    _createRefactoringForString('1 + 2');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
class A {
  A(int v) {}
}
class B extends A {
  B() : super(res()) {}

  static int res() => 1 + 2;
}
''');
  }

  test_singleExpression_staticContext_extractFromInstance() {
    indexTestUnit('''
class A {
  instanceMethodA() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = v1 + v2; // marker
  }
  instanceMethodB() {
    int v1 = 1;
    int v2 = 2;
    int positiveB = v1 + v2;
  }
  static staticMethodA() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = v1 + v2;
  }
}
''');
    _createRefactoringWithSuffix('v1 + v2', '; // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
class A {
  instanceMethodA() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = res(v1, v2); // marker
  }

  static int res(int v1, int v2) => v1 + v2;
  instanceMethodB() {
    int v1 = 1;
    int v2 = 2;
    int positiveB = res(v1, v2);
  }
  static staticMethodA() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = res(v1, v2);
  }
}
''');
  }

  test_singleExpression_staticContext_extractFromStatic() {
    indexTestUnit('''
class A {
  static staticMethodA() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = v1 + v2; // marker
  }
  static staticMethodB() {
    int v1 = 1;
    int v2 = 2;
    int positiveB = v1 + v2;
  }
  instanceMethodA() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = v1 + v2;
  }
}
''');
    _createRefactoringWithSuffix('v1 + v2', '; // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
class A {
  static staticMethodA() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = res(v1, v2); // marker
  }

  static int res(int v1, int v2) => v1 + v2;
  static staticMethodB() {
    int v1 = 1;
    int v2 = 2;
    int positiveB = res(v1, v2);
  }
  instanceMethodA() {
    int v1 = 1;
    int v2 = 2;
    int positiveA = res(v1, v2);
  }
}
''');
  }

  test_singleExpression_staticContext_hasInInitializer() {
    indexTestUnit('''
class A {
  A(int v) {}
}
class B extends A {
  B() : super(1 + 2) {}
  foo() {
    print(1 + 2); // marker
  }
}
''');
    _createRefactoringWithSuffix('1 + 2', '); // marker');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
class A {
  A(int v) {}
}
class B extends A {
  B() : super(res()) {}
  foo() {
    print(res()); // marker
  }

  static int res() => 1 + 2;
}
''');
  }

  test_singleExpression_usesParameter() {
    indexTestUnit('''
fooA(int a1) {
  int a2 = 2;
  int a = a1 + a2;
}
fooB(int b1) {
  int b2 = 2;
  int b = b1 + b2;
}
''');
    _createRefactoringForString('a1 + a2');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
fooA(int a1) {
  int a2 = 2;
  int a = res(a1, a2);
}

int res(int a1, int a2) => a1 + a2;
fooB(int b1) {
  int b2 = 2;
  int b = res(b1, b2);
}
''');
  }

  test_singleExpression_withVariables() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
  int a = v1 + v2 + v1;
}
''');
    _createRefactoringForString('v1 + v2 + v1');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  int v1 = 1;
  int v2 = 2;
  int a = res(v1, v2);
}

int res(int v1, int v2) => v1 + v2 + v1;
''');
  }

  test_singleExpression_withVariables_doRename() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int a = v1 + v2 + v1; // marker
  int b = v2 + v3 + v2;
}
''');
    _createRefactoringForString('v1 + v2 + v1');
    // apply refactoring
    return refactoring.checkInitialConditions().then((_) {
      {
        var parameters = _getParametersCopy();
        expect(parameters, hasLength(2));
        expect(parameters[0].name, 'v1');
        expect(parameters[1].name, 'v2');
        parameters[0].name = 'par1';
        parameters[1].name = 'param2';
        refactoring.parameters = parameters;
      }
      return assertRefactoringFinalConditionsOK().then((_) {
        refactoring.createGetter = false;
        return _assertRefactoringChange('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int a = res(v1, v2); // marker
  int b = res(v2, v3);
}

int res(int par1, int param2) => par1 + param2 + par1;
''');
      });
    });
  }

  test_singleExpression_withVariables_doReorder() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int a = v1 + v2; // marker
  int b = v2 + v3;
}
''');
    _createRefactoringForString('v1 + v2');
    // apply refactoring
    return refactoring.checkInitialConditions().then((_) {
      {
        var parameters = _getParametersCopy();
        expect(parameters, hasLength(2));
        expect(parameters[0].name, 'v1');
        expect(parameters[1].name, 'v2');
        var parameter = parameters.removeAt(1);
        parameters.insert(0, parameter);
        refactoring.parameters = parameters;
      }
      return assertRefactoringFinalConditionsOK().then((_) {
        refactoring.createGetter = false;
        return _assertRefactoringChange('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int a = res(v2, v1); // marker
  int b = res(v3, v2);
}

int res(int v2, int v1) => v1 + v2;
''');
      });
    });
  }

  test_singleExpression_withVariables_namedExpression() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
  int a = process(arg: v1 + v2);
}
process({arg}) {}
''');
    _createRefactoringForString('process(arg: v1 + v2)');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  int v1 = 1;
  int v2 = 2;
  int a = res(v1, v2);
}

res(int v1, int v2) => process(arg: v1 + v2);
process({arg}) {}
''');
  }

  test_singleExpression_withVariables_newType() {
    indexTestUnit('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int a = v1 + v2 + v3;
}
''');
    _createRefactoringForString('v1 + v2 + v3');
    // apply refactoring
    return refactoring.checkInitialConditions().then((_) {
      {
        var parameters = _getParametersCopy();
        expect(parameters, hasLength(3));
        expect(parameters[0].name, 'v1');
        expect(parameters[1].name, 'v2');
        expect(parameters[2].name, 'v3');
        parameters[0].type = 'num';
        parameters[1].type = 'dynamic';
        parameters[2].type = '';
        refactoring.parameters = parameters;
      }
      return assertRefactoringFinalConditionsOK().then((_) {
        refactoring.createGetter = false;
        return _assertRefactoringChange('''
main() {
  int v1 = 1;
  int v2 = 2;
  int v3 = 3;
  int a = res(v1, v2, v3);
}

int res(num v1, v2, v3) => v1 + v2 + v3;
''');
      });
    });
  }

  test_singleExpression_withVariables_useBestType() {
    indexTestUnit('''
main() {
  var v1 = 1;
  var v2 = 2;
  var a = v1 + v2 + v1; // marker
}
''');
    _createRefactoringForString('v1 + v2 + v1');
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  var v1 = 1;
  var v2 = 2;
  var a = res(v1, v2); // marker
}

num res(int v1, int v2) => v1 + v2 + v1;
''');
  }

  test_statements_assignment() {
    indexTestUnit('''
main() {
  int v;
// start
  v = 5;
// end
  print(v);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  int v;
// start
  v = res(v);
// end
  print(v);
}

int res(int v) {
  v = 5;
  return v;
}
''');
  }

  test_statements_changeIndentation() {
    indexTestUnit('''
main() {
  {
// start
    if (true) {
      print(0);
    }
// end
  }
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  {
// start
    res();
// end
  }
}

void res() {
  if (true) {
    print(0);
  }
}
''');
  }

  test_statements_changeIndentation_multilineString() {
    indexTestUnit('''
main() {
  {
// start
    print("""
first line
second line
    """);
// end
  }
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  {
// start
    res();
// end
  }
}

void res() {
  print("""
first line
second line
    """);
}
''');
  }

  test_statements_definesVariable_notUsedOutside() {
    indexTestUnit('''
main() {
  int a = 1;
  int b = 1;
// start
  int v = a + b;
  print(v);
// end
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  int a = 1;
  int b = 1;
// start
  res(a, b);
// end
}

void res(int a, int b) {
  int v = a + b;
  print(v);
}
''');
  }

  test_statements_definesVariable_oneUsedOutside_assignment() {
    indexTestUnit('''
myFunctionA() {
  int a = 1;
// start
  a += 10;
// end
  print(a);
}
myFunctionB() {
  int b = 2;
  b += 10;
  print(b);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
myFunctionA() {
  int a = 1;
// start
  a = res(a);
// end
  print(a);
}

int res(int a) {
  a += 10;
  return a;
}
myFunctionB() {
  int b = 2;
  b = res(b);
  print(b);
}
''');
  }

  test_statements_definesVariable_oneUsedOutside_declaration() {
    indexTestUnit('''
myFunctionA() {
  int a = 1;
  int b = 2;
// start
  int v1 = a + b;
// end
  print(v1);
}
myFunctionB() {
  int a = 3;
  int b = 4;
  int v2 = a + b;
  print(v2);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
myFunctionA() {
  int a = 1;
  int b = 2;
// start
  int v1 = res(a, b);
// end
  print(v1);
}

int res(int a, int b) {
  int v1 = a + b;
  return v1;
}
myFunctionB() {
  int a = 3;
  int b = 4;
  int v2 = res(a, b);
  print(v2);
}
''');
  }

  test_statements_definesVariable_twoUsedOutside() {
    indexTestUnit('''
main() {
// start
  int varA = 1;
  int varB = 2;
// end
  int v = varA + varB;
}
''');
    _createRefactoringForStartEndComments();
    // check conditions
    return refactoring.checkInitialConditions().then((status) {
      assertRefactoringStatus(status, RefactoringProblemSeverity.FATAL);
    });
  }

  test_statements_duplicate_absolutelySame() {
    indexTestUnit('''
myFunctionA() {
  print(0);
  print(1);
}
myFunctionB() {
// start
  print(0);
  print(1);
// end
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
myFunctionA() {
  res();
}
myFunctionB() {
// start
  res();
// end
}

void res() {
  print(0);
  print(1);
}
''');
  }

  test_statements_duplicate_declaresDifferentlyNamedVariable() {
    indexTestUnit('''
myFunctionA() {
  int varA = 1;
  print(varA);
}
myFunctionB() {
// start
  int varB = 1;
  print(varB);
// end
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
myFunctionA() {
  res();
}
myFunctionB() {
// start
  res();
// end
}

void res() {
  int varB = 1;
  print(varB);
}
''');
  }

  test_statements_dynamic() {
    indexTestUnit('''
dynaFunction(p) => 0;
main() {
// start
  var a = 1;
  var v = dynaFunction(a);
// end
  print(v);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
dynaFunction(p) => 0;
main() {
// start
  var v = res();
// end
  print(v);
}

res() {
  var a = 1;
  var v = dynaFunction(a);
  return v;
}
''');
  }

  /**
   * We should always add ";" when invoke method with extracted statements.
   */
  test_statements_endsWithBlock() {
    indexTestUnit('''
main() {
// start
  if (true) {
    print(0);
  }
// end
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
// start
  res();
// end
}

void res() {
  if (true) {
    print(0);
  }
}
''');
  }

  test_statements_inSwitchMember() {
    indexTestUnit('''
class A {
  foo(int p) {
    switch (p) {
      case 0:
// start
        print(0);
// end
        break;
      default:
        break;
    }
  }
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
class A {
  foo(int p) {
    switch (p) {
      case 0:
// start
        res();
// end
        break;
      default:
        break;
    }
  }

  void res() {
    print(0);
  }
}
''');
  }

  test_statements_method() {
    indexTestUnit('''
class A {
  foo() {
// start
    print(0);
// end
  }
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
class A {
  foo() {
// start
    res();
// end
  }

  void res() {
    print(0);
  }
}
''');
  }

  test_statements_noDuplicates() {
    indexTestUnit('''
main() {
  int a = 1;
  int b = 1;
// start
  print(a);
// end
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
  int a = 1;
  int b = 1;
// start
  res(a);
// end
}

void res(int a) {
  print(a);
}
''');
  }

  test_statements_return_last() {
    indexTestUnit('''
main() {
// start
  int v = 5;
  return v + 1;
// end
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
// start
  return res();
// end
}

int res() {
  int v = 5;
  return v + 1;
}
''');
  }

  test_statements_return_single() {
    indexTestUnit('''
main() {
// start
  return 42;
// end
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
// start
  return res();
// end
}

int res() {
  return 42;
}
''');
  }

  /**
   * We have 3 identical statements, but select only 2.
   * This should not cause problems.
   */
  test_statements_twoOfThree() {
    indexTestUnit('''
main() {
// start
  print(0);
  print(0);
// end
  print(0);
}
''');
    _createRefactoringForStartEndComments();
    // apply refactoring
    return _assertSuccessfulRefactoring('''
main() {
// start
  res();
// end
  print(0);
}

void res() {
  print(0);
  print(0);
}
''');
  }

  Future _assertConditionsError(String message) {
    return refactoring.checkAllConditions().then((status) {
      assertRefactoringStatus(
          status,
          RefactoringProblemSeverity.ERROR,
          expectedMessage: message);
    });
  }

  Future _assertConditionsFatal(String message) {
    return refactoring.checkAllConditions().then((status) {
      assertRefactoringStatus(
          status,
          RefactoringProblemSeverity.FATAL,
          expectedMessage: message);
    });
  }

  Future _assertFinalConditionsError(String message) {
    return refactoring.checkFinalConditions().then((status) {
      assertRefactoringStatus(
          status,
          RefactoringProblemSeverity.ERROR,
          expectedMessage: message);
    });
  }

  Future _assertRefactoringChange(String expectedCode) {
    return refactoring.createChange().then((SourceChange refactoringChange) {
      this.refactoringChange = refactoringChange;
      assertTestChangeResult(expectedCode);
    });
  }

  /**
   * Checks that all conditions are OK and the result of applying the [Change]
   * to [testUnit] is [expectedCode].
   */
  Future _assertSuccessfulRefactoring(String expectedCode) {
    return assertRefactoringConditionsOK().then((_) {
      refactoring.createGetter = false;
      return _assertRefactoringChange(expectedCode);
    });
  }

  void _createRefactoring(int offset, int length) {
    refactoring =
        new ExtractMethodRefactoring(searchEngine, testUnit, offset, length);
    refactoring.name = 'res';
  }

  void _createRefactoringForStartEndComments() {
    int offset = findEnd('// start') + '\n'.length;
    int end = findOffset('// end');
    _createRefactoring(offset, end - offset);
  }

  void _createRefactoringForStartEndString(String startSearch,
      String endSearch) {
    int offset = findOffset(startSearch);
    int end = findOffset(endSearch);
    _createRefactoring(offset, end - offset);
  }

  /**
   * Creates a new refactoring in [refactoring] for the selection range of the
   * given [search] pattern.
   */
  void _createRefactoringForString(String search) {
    int offset = findOffset(search);
    int length = search.length;
    _createRefactoring(offset, length);
  }

  void _createRefactoringWithSuffix(String selectionSearch, String suffix) {
    int offset = findOffset(selectionSearch + suffix);
    int length = selectionSearch.length;
    _createRefactoring(offset, length);
  }

  /**
   * Returns a deep copy of [refactoring] parameters.
   * There was a bug masked by updating parameter instances shared between the
   * refactoring and the test.
   */
  List<RefactoringMethodParameter> _getParametersCopy() {
    return refactoring.parameters.map((p) {
      return new RefactoringMethodParameter(p.kind, p.type, p.name, id: p.id);
    }).toList();
  }
}
