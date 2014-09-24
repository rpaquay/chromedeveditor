// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.outline_builder;

import 'package:analyzer_clone/src/generated/ast.dart' as ast;

import 'services_common.dart';

/**
 * Utility class to build [Outline] instances.
 */
class OutlineBuilder {
  /**
   * Builds an [Outline] instance from a [ast.CompilationUnit] instance.
   */
  Outline build(ast.CompilationUnit compilationUnit) {
    Outline outline = new Outline();

    // Ideally, we'd get an AST back, even for very badly formed files.
    if (compilationUnit == null) return outline;

    // TODO(ericarnold): Need to implement modifiers
    // TODO(ericarnold): Need to implement types

    for (ast.Declaration declaration in compilationUnit.declarations) {
      if (declaration is ast.TopLevelVariableDeclaration) {
        _addVariableToOutline(outline, declaration);
      } else if (declaration is ast.FunctionDeclaration) {
        _addFunctionToOutline(outline, declaration);
      } else if (declaration is ast.ClassDeclaration) {
        _addClassToOutline(outline, declaration);
      } else if (declaration is ast.TypeAlias) {
        _addAliasToOutline(outline, declaration);
      } else {
        print("${declaration.runtimeType} is unknown");
      }
    }

    return outline;
  }

  void _addVariableToOutline(
      Outline outline, ast.TopLevelVariableDeclaration declaration) {
    ast.VariableDeclarationList variables = declaration.variables;

    for (ast.VariableDeclaration variable in variables.variables) {
      outline.entries.add(_populateOutlineEntry(
          new OutlineTopLevelVariable(variable.name.name,
              _getTypeNameString(variables.type)),
          new Range.fromAstNode(declaration),
          new Range.fromAstNode(declaration)));
    }
  }

  void _addFunctionToOutline(
      Outline outline, ast.FunctionDeclaration declaration) {
    ast.SimpleIdentifier nameNode = declaration.name;
    Range nameRange = new Range.fromAstNode(nameNode);
    Range bodyRange = new Range.fromAstNode(declaration);
    String name = nameNode.name;

    if (declaration.isGetter) {
      outline.entries.add(_populateOutlineEntry(
          new OutlineTopLevelAccessor(name, _getTypeNameString(declaration.returnType)),
          nameRange, bodyRange));
    } else if (declaration.isSetter) {
      ast.FormalParameterList params =
          declaration.functionExpression.parameters;
      outline.entries.add(_populateOutlineEntry(
          new OutlineTopLevelAccessor(name,
              _getSetterTypeFromParams(params), true),
          nameRange, bodyRange));
    } else {
      outline.entries.add(_populateOutlineEntry(
          new OutlineTopLevelFunction(name,
              _getTypeNameString(declaration.returnType)),
              nameRange, bodyRange));
    }
  }

  void _addClassToOutline(Outline outline,
      ast.ClassDeclaration declaration) {
    OutlineClass outlineClass = new OutlineClass(declaration.name.name);
    outline.entries.add(
        _populateOutlineEntry(outlineClass,
                              new Range.fromAstNode(declaration.name),
                              new Range.fromAstNode(declaration)));

    for (ast.ClassMember member in declaration.members) {
      if (member is ast.MethodDeclaration) {
        _addMethodToOutlineClass(outlineClass, member);
      } else if (member is ast.FieldDeclaration) {
        _addFieldToOutlineClass(outlineClass, member);
      } else if (member is ast.ConstructorDeclaration) {
        _addConstructorToOutlineClass(outlineClass, member, declaration);
      }
    }
  }

  void _addAliasToOutline(Outline outline, ast.TypeAlias declaration) {
    ast.SimpleIdentifier nameNode;

    if (declaration is ast.ClassTypeAlias) {
      nameNode = declaration.name;
    } else if (declaration is ast.FunctionTypeAlias) {
      nameNode = declaration.name;
    } else {
      throw "TypeAlias subclass ${declaration.runtimeType} is unknown";
    }

    String name = nameNode.name;

    outline.entries.add(_populateOutlineEntry(new OutlineTypeDef(name),
        new Range.fromAstNode(nameNode), new Range.fromAstNode(declaration)));
  }

  void _addMethodToOutlineClass(OutlineClass outlineClass,
                                ast.MethodDeclaration member) {

    if (member.isGetter) {
      outlineClass.members.add(_populateOutlineEntry(
          new OutlineClassAccessor(member.name.name,
              _getTypeNameString(member.returnType)),
          new Range.fromAstNode(member.name),
          new Range.fromAstNode(member)));
    } else if (member.isSetter) {
      outlineClass.members.add(_populateOutlineEntry(
          new OutlineClassAccessor(member.name.name,
              _getSetterTypeFromParams(member.parameters), true),
          new Range.fromAstNode(member.name),
          new Range.fromAstNode(member)));
    } else {
      outlineClass.members.add(_populateOutlineEntry(
          new OutlineMethod(member.name.name, _getTypeNameString(member.returnType)),
          new Range.fromAstNode(member.name),
          new Range.fromAstNode(member)));
    }
  }

  void _addFieldToOutlineClass(OutlineClass outlineClass,
                               ast.FieldDeclaration member) {
    ast.VariableDeclarationList fields = member.fields;
    for (ast.VariableDeclaration field in fields.variables) {
      outlineClass.members.add(_populateOutlineEntry(
          new OutlineProperty(field.name.name, _getTypeNameString(fields.type)),
          new Range.fromAstNode(field),
          new Range.fromAstNode(field.parent)));
    }
  }

  void _addConstructorToOutlineClass(OutlineClass outlineClass,
                                     ast.ConstructorDeclaration member,
                                      ast.ClassDeclaration classDeclaration) {
    ast.ConstructorDeclaration constructor = member;

    var nameIdentifier = constructor.name;
    String name = classDeclaration.name.name +
        (nameIdentifier != null ? ".${nameIdentifier.name}" : "");
    Range nameRange = new Range(constructor.beginToken.offset,
        nameIdentifier == null ? constructor.beginToken.end :
        nameIdentifier.end);

    outlineClass.members.add(_populateOutlineEntry(
        new OutlineMethod(name),
        nameRange,
        new Range.fromAstNode(classDeclaration)));
  }

  OutlineEntry _populateOutlineEntry(OutlineEntry outlineEntry, Range name,
      Range body) {
    outlineEntry.nameStartOffset = name.startOffset;
    outlineEntry.nameEndOffset = name.endOffset;
    outlineEntry.bodyStartOffset = body.startOffset;
    outlineEntry.bodyEndOffset = body.endOffset;
    return outlineEntry;
  }

  /**
   * Returns a [ast.TypeName] as a user friendly display string.
   */
  String _getTypeNameString(ast.TypeName typeName) {
    if (typeName == null) return null;

    ast.Identifier identifier = typeName.name;
    if (identifier == null) return null;

    String name = identifier.name;
    if (name == null) return null;

    int index = name.lastIndexOf('.');
    return index == -1 ? name : name.substring(index + 1);
  }

  String _getSetterTypeFromParams(ast.FormalParameterList parameters) {
    // Only show type of first [analyzer.SimpleFormalParameter] of setter.
    if (parameters.parameters.length > 0) {
      ast.FormalParameter param = parameters.parameters.first;
      if (param is ast.SimpleFormalParameter) {
        return _getTypeNameString(param.type);
      }
    }

    return null;
  }
}

class Range {
  final int startOffset;
  final int endOffset;

  Range(this.startOffset, this.endOffset);
  Range.fromAstNode(ast.AstNode node)
    : this.startOffset = node.offset, this.endOffset = node.end;
}
