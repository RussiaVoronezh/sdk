// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../common/names.dart';
import '../common_elements.dart';
import '../util/util.dart' show equalElements;
import 'entities.dart';

/// Hierarchy to describe types in Dart.
///
/// This hierarchy is a super hierarchy of the use-case specific hierarchies
/// used in different parts of the compiler. This hierarchy abstracts details
/// not generally needed or required for the Dart type hierarchy. For instance,
/// the hierarchy in 'resolution_types.dart' has properties supporting lazy
/// computation (like computeAlias) and distinctions between 'Foo' and
/// 'Foo<dynamic>', features that are not needed for code generation and not
/// supported from kernel.
///
/// Current only 'resolution_types.dart' implement this hierarchy but when the
/// compiler moves to use [Entity] instead of [Element] this hierarchy can be
/// implemented directly but other entity systems, for instance based directly
/// on kernel ir without the need for [Element].

abstract class DartType {
  const DartType();

  /// Returns the unaliased type of this type.
  ///
  /// The unaliased type of a typedef'd type is the unaliased type to which its
  /// name is bound. The unaliased version of any other type is the type itself.
  ///
  /// For example, the unaliased type of `typedef A Func<A,B>(B b)` is the
  /// function type `(B) -> A` and the unaliased type of `Func<int,String>`
  /// is the function type `(String) -> int`.
  DartType get unaliased => this;

  /// Is `true` if this type has no non-dynamic type arguments.
  bool get treatAsRaw => true;

  /// Is `true` if this type should be treated as the dynamic type.
  bool get treatAsDynamic => false;

  /// Is `true` if this type is the dynamic type.
  bool get isDynamic => false;

  /// Is `true` if this type is the void type.
  bool get isVoid => false;

  /// Is `true` if this type is an interface type.
  bool get isInterfaceType => false;

  /// Is `true` if this type is a typedef.
  bool get isTypedef => false;

  /// Is `true` if this type is a function type.
  bool get isFunctionType => false;

  /// Is `true` if this type is a type variable.
  bool get isTypeVariable => false;

  /// Is `true` if this type is a type variable declared on a function type
  ///
  /// For instance `T` in
  ///     void Function<T>(T t)
  bool get isFunctionTypeVariable => false;

  /// Is `true` if this type is a `FutureOr` type.
  bool get isFutureOr => false;

  /// Is `true` if this type is a malformed type.
  bool get isMalformed => false;

  /// Whether this type contains a type variable.
  bool get containsTypeVariables => false;

  /// Is `true` if this type is the 'Object' type defined in 'dart:core'.
  bool get isObject => false;

  /// Applies [f] to each occurence of a [TypeVariableType] within this
  /// type. This excludes function type variables, whether free or bound.
  void forEachTypeVariable(f(TypeVariableType variable)) {}

  /// Performs the substitution `[arguments[i]/parameters[i]]this`.
  ///
  /// The notation is known from this lambda calculus rule:
  ///
  ///     (lambda x.e0)e1 -> [e1/x]e0.
  ///
  /// See [TypeVariableType] for a motivation for this method.
  ///
  /// Invariant: There must be the same number of [arguments] and [parameters].
  DartType subst(List<DartType> arguments, List<DartType> parameters);

  /// Calls the visit method on [visitor] corresponding to this type.
  R accept<R, A>(DartTypeVisitor<R, A> visitor, A argument);

  bool _equals(DartType other, _Assumptions assumptions);
}

/// Pairs of [FunctionTypeVariable]s that are currently assumed to be equivalent.
///
/// This is used to compute the equivalence relation on types coinductively.
class _Assumptions {
  Map<FunctionTypeVariable, Set<FunctionTypeVariable>> _assumptionMap =
      <FunctionTypeVariable, Set<FunctionTypeVariable>>{};

  void _addAssumption(FunctionTypeVariable a, FunctionTypeVariable b) {
    _assumptionMap
        .putIfAbsent(a, () => new Set<FunctionTypeVariable>.identity())
        .add(b);
  }

  /// Assume that [a] and [b] are equivalent.
  void assume(FunctionTypeVariable a, FunctionTypeVariable b) {
    _addAssumption(a, b);
    _addAssumption(b, a);
  }

  void _removeAssumption(FunctionTypeVariable a, FunctionTypeVariable b) {
    Set<FunctionTypeVariable> set = _assumptionMap[a];
    if (set != null) {
      set.remove(b);
      if (set.isEmpty) {
        _assumptionMap.remove(a);
      }
    }
  }

  /// Remove the assumption that [a] and [b] are equivalent.
  void forget(FunctionTypeVariable a, FunctionTypeVariable b) {
    _removeAssumption(a, b);
    _removeAssumption(b, a);
  }

  /// Returns `true` if [a] and [b] are assumed to be equivalent.
  bool isAssumed(FunctionTypeVariable a, FunctionTypeVariable b) {
    return _assumptionMap[a]?.contains(b) ?? false;
  }

  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write('_Assumptions(');
    String comma = '';
    _assumptionMap
        .forEach((FunctionTypeVariable a, Set<FunctionTypeVariable> set) {
      sb.write('$comma$a (${identityHashCode(a)})->'
          '{${set.map((b) => '$b (${identityHashCode(b)})').join(',')}}');
      comma = ',';
    });
    sb.write(')');
    return sb.toString();
  }
}

class InterfaceType extends DartType {
  final ClassEntity element;
  final List<DartType> typeArguments;

  InterfaceType(this.element, this.typeArguments);

  bool get isInterfaceType => true;

  bool get isObject {
    return element.name == 'Object' &&
        element.library.canonicalUri == Uris.dart_core;
  }

  bool get containsTypeVariables =>
      typeArguments.any((type) => type.containsTypeVariables);

  void forEachTypeVariable(f(TypeVariableType variable)) {
    typeArguments.forEach((type) => type.forEachTypeVariable(f));
  }

  InterfaceType subst(List<DartType> arguments, List<DartType> parameters) {
    if (typeArguments.isEmpty) {
      // Return fast on non-generic types.
      return this;
    }
    if (parameters.isEmpty) {
      assert(arguments.isEmpty);
      // Return fast on empty substitutions.
      return this;
    }
    List<DartType> newTypeArguments =
        _substTypes(typeArguments, arguments, parameters);
    if (!identical(typeArguments, newTypeArguments)) {
      // Create a new type only if necessary.
      return new InterfaceType(element, newTypeArguments);
    }
    return this;
  }

  bool get treatAsRaw {
    for (DartType type in typeArguments) {
      if (!type.treatAsDynamic) return false;
    }
    return true;
  }

  @override
  R accept<R, A>(DartTypeVisitor<R, A> visitor, A argument) =>
      visitor.visitInterfaceType(this, argument);

  int get hashCode {
    int hash = element.hashCode;
    for (DartType argument in typeArguments) {
      int argumentHash = argument != null ? argument.hashCode : 0;
      hash = 17 * hash + 3 * argumentHash;
    }
    return hash;
  }

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! InterfaceType) return false;
    return _equalsInternal(other, null);
  }

  bool _equals(DartType other, _Assumptions assumptions) {
    if (identical(this, other)) return true;
    if (other is! InterfaceType) return false;
    return _equalsInternal(other, assumptions);
  }

  bool _equalsInternal(InterfaceType other, _Assumptions assumptions) {
    return identical(element, other.element) &&
        _equalTypes(typeArguments, other.typeArguments, assumptions);
  }

  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write(element.name);
    if (typeArguments.isNotEmpty) {
      sb.write('<');
      bool needsComma = false;
      for (DartType typeArgument in typeArguments) {
        if (needsComma) {
          sb.write(',');
        }
        sb.write(typeArgument);
        needsComma = true;
      }
      sb.write('>');
    }
    return sb.toString();
  }
}

class TypedefType extends DartType {
  final TypedefEntity element;
  final List<DartType> typeArguments;

  TypedefType(this.element, this.typeArguments);

  bool get isTypedef => true;

  bool get containsTypeVariables =>
      typeArguments.any((type) => type.containsTypeVariables);

  void forEachTypeVariable(f(TypeVariableType variable)) {
    typeArguments.forEach((type) => type.forEachTypeVariable(f));
  }

  TypedefType subst(List<DartType> arguments, List<DartType> parameters) {
    if (typeArguments.isEmpty) {
      // Return fast on non-generic types.
      return this;
    }
    if (parameters.isEmpty) {
      assert(arguments.isEmpty);
      // Return fast on empty substitutions.
      return this;
    }
    List<DartType> newTypeArguments =
        _substTypes(typeArguments, arguments, parameters);
    if (!identical(typeArguments, newTypeArguments)) {
      // Create a new type only if necessary.
      return new TypedefType(element, newTypeArguments);
    }
    return this;
  }

  bool get treatAsRaw {
    for (DartType type in typeArguments) {
      if (!type.treatAsDynamic) return false;
    }
    return true;
  }

  @override
  R accept<R, A>(DartTypeVisitor<R, A> visitor, A argument) =>
      visitor.visitTypedefType(this, argument);

  int get hashCode {
    int hash = element.hashCode;
    for (DartType argument in typeArguments) {
      int argumentHash = argument != null ? argument.hashCode : 0;
      hash = 17 * hash + 3 * argumentHash;
    }
    return hash;
  }

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! TypedefType) return false;
    return _equalsInternal(other, null);
  }

  bool _equals(DartType other, _Assumptions assumptions) {
    if (identical(this, other)) return true;
    if (other is! TypedefType) return false;
    return _equalsInternal(other, assumptions);
  }

  bool _equalsInternal(TypedefType other, _Assumptions assumptions) {
    return identical(element, other.element) &&
        _equalTypes(typeArguments, other.typeArguments, assumptions);
  }

  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write(element.name);
    if (typeArguments.isNotEmpty) {
      sb.write('<');
      bool needsComma = false;
      for (DartType typeArgument in typeArguments) {
        if (needsComma) {
          sb.write(',');
        }
        sb.write(typeArgument);
        needsComma = true;
      }
      sb.write('>');
    }
    return sb.toString();
  }
}

/// Provides a thin model of method type variables for compabitility with the
/// old compiler behavior in Dart 1: They are treated as if their value were
/// `dynamic` when used in a type annotation, and as a malformed type when
/// used in an `as` or `is` expression.
class Dart1MethodTypeVariableType extends TypeVariableType {
  Dart1MethodTypeVariableType(TypeVariableEntity element) : super(element);

  @override
  bool get treatAsDynamic => true;

  @override
  bool get isMalformed => true;
}

class TypeVariableType extends DartType {
  final TypeVariableEntity element;

  TypeVariableType(this.element);

  bool get isTypeVariable => true;

  bool get containsTypeVariables => true;

  void forEachTypeVariable(f(TypeVariableType variable)) {
    f(this);
  }

  DartType subst(List<DartType> arguments, List<DartType> parameters) {
    assert(arguments.length == parameters.length);
    if (parameters.isEmpty) {
      // Return fast on empty substitutions.
      return this;
    }
    int index = parameters.indexOf(this);
    if (index != -1) {
      return arguments[index];
    }
    // The type variable was not substituted.
    return this;
  }

  @override
  R accept<R, A>(DartTypeVisitor<R, A> visitor, A argument) =>
      visitor.visitTypeVariableType(this, argument);

  int get hashCode => 17 * element.hashCode;

  bool operator ==(other) {
    if (other is! TypeVariableType) return false;
    return identical(other.element, element);
  }

  @override
  bool _equals(DartType other, _Assumptions assumptions) {
    if (other is TypeVariableType) {
      return identical(other.element, element);
    }
    return false;
  }

  String toString() => '${element.typeDeclaration.name}.${element.name}';
}

/// A type variable declared on a function type.
///
/// For instance `T` in
///     void Function<T>(T t)
///
/// Such a type variable is different from a [TypeVariableType] because it
/// doesn't have a unique identity; is is equal to any other
/// [FunctionTypeVariable] used similarly in another structurally equivalent
/// function type.
class FunctionTypeVariable extends DartType {
  /// The index of this type within the type variables of the declaring function
  /// type.
  final int index;

  /// The bound of this function type variable.
  DartType _bound;

  FunctionTypeVariable(this.index);

  DartType get bound {
    assert(_bound != null, "Bound hasn't been set.");
    return _bound;
  }

  void set bound(DartType value) {
    assert(_bound == null, "Bound has already been set.");
    _bound = value;
  }

  @override
  bool get isFunctionTypeVariable => true;

  DartType subst(List<DartType> arguments, List<DartType> parameters) {
    assert(arguments.length == parameters.length);
    if (parameters.isEmpty) {
      // Return fast on empty substitutions.
      return this;
    }
    int index = parameters.indexOf(this);
    if (index != -1) {
      return arguments[index];
    }
    // The function type variable was not substituted.
    return this;
  }

  int get hashCode => index.hashCode * 19;

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! FunctionTypeVariable) return false;
    return false;
  }

  @override
  bool _equals(DartType other, _Assumptions assumptions) {
    if (identical(this, other)) return true;
    if (other is! FunctionTypeVariable) return false;
    if (assumptions != null) return assumptions.isAssumed(this, other);
    return false;
  }

  @override
  R accept<R, A>(DartTypeVisitor<R, A> visitor, A argument) =>
      visitor.visitFunctionTypeVariable(this, argument);

  String toString() => '#${new String.fromCharCode(0x41 + index)}';
}

class VoidType extends DartType {
  const VoidType();

  bool get isVoid => true;

  DartType subst(List<DartType> arguments, List<DartType> parameters) {
    // `void` cannot be substituted.
    return this;
  }

  @override
  R accept<R, A>(DartTypeVisitor<R, A> visitor, A argument) =>
      visitor.visitVoidType(this, argument);

  int get hashCode => 6007;

  @override
  bool _equals(DartType other, _Assumptions assumptions) {
    return identical(this, other);
  }

  String toString() => 'void';
}

class DynamicType extends DartType {
  const DynamicType();

  @override
  bool get isDynamic => true;

  @override
  bool get treatAsDynamic => true;

  DartType subst(List<DartType> arguments, List<DartType> parameters) {
    // `dynamic` cannot be substituted.
    return this;
  }

  @override
  R accept<R, A>(DartTypeVisitor<R, A> visitor, A argument) =>
      visitor.visitDynamicType(this, argument);

  int get hashCode => 91;

  @override
  bool _equals(DartType other, _Assumptions assumptions) {
    return identical(this, other);
  }

  String toString() => 'dynamic';
}

class FunctionType extends DartType {
  final DartType returnType;
  final List<DartType> parameterTypes;
  final List<DartType> optionalParameterTypes;

  /// The names of the named parameters ordered lexicographically.
  final List<String> namedParameters;

  /// The types of the named parameters in the order corresponding to the
  /// [namedParameters].
  final List<DartType> namedParameterTypes;

  final List<FunctionTypeVariable> typeVariables;

  /// The originating [TypedefType], if any.
  final TypedefType typedefType;

  FunctionType(
      this.returnType,
      this.parameterTypes,
      this.optionalParameterTypes,
      this.namedParameters,
      this.namedParameterTypes,
      this.typeVariables,
      this.typedefType);

  bool get containsTypeVariables {
    return typeVariables.any((type) => type.bound.containsTypeVariables) ||
        returnType.containsTypeVariables ||
        parameterTypes.any((type) => type.containsTypeVariables) ||
        optionalParameterTypes.any((type) => type.containsTypeVariables) ||
        namedParameterTypes.any((type) => type.containsTypeVariables);
  }

  void forEachTypeVariable(f(TypeVariableType variable)) {
    typeVariables.forEach((type) => type.bound.forEachTypeVariable(f));
    returnType.forEachTypeVariable(f);
    parameterTypes.forEach((type) => type.forEachTypeVariable(f));
    optionalParameterTypes.forEach((type) => type.forEachTypeVariable(f));
    namedParameterTypes.forEach((type) => type.forEachTypeVariable(f));
  }

  bool get isFunctionType => true;

  DartType subst(List<DartType> arguments, List<DartType> parameters) {
    if (parameters.isEmpty) {
      assert(arguments.isEmpty);
      // Return fast on empty substitutions.
      return this;
    }
    DartType newReturnType = returnType.subst(arguments, parameters);
    bool changed = !identical(newReturnType, returnType);
    List<DartType> newParameterTypes =
        _substTypes(parameterTypes, arguments, parameters);
    List<DartType> newOptionalParameterTypes =
        _substTypes(optionalParameterTypes, arguments, parameters);
    List<DartType> newNamedParameterTypes =
        _substTypes(namedParameterTypes, arguments, parameters);
    if (!changed &&
        (!identical(parameterTypes, newParameterTypes) ||
            !identical(optionalParameterTypes, newOptionalParameterTypes) ||
            !identical(namedParameterTypes, newNamedParameterTypes))) {
      changed = true;
    }
    List<FunctionTypeVariable> newTypeVariables;
    if (typeVariables.isNotEmpty) {
      if (parameters == typeVariables) {
        newTypeVariables = const <FunctionTypeVariable>[];
        changed = true;
      } else {
        int index = 0;
        for (FunctionTypeVariable typeVariable in typeVariables) {
          DartType newBound = typeVariable.bound.subst(arguments, parameters);
          if (!identical(typeVariable.bound, newBound)) {
            newTypeVariables ??= typeVariables.sublist(0, index);
            changed = true;
          } else {
            newTypeVariables?.add(typeVariable);
          }
          index++;
        }
        newTypeVariables ??= typeVariables;
      }
    } else {
      newTypeVariables = typeVariables;
    }
    if (changed) {
      // Create a new type only if necessary.
      return new FunctionType(
          newReturnType,
          newParameterTypes,
          newOptionalParameterTypes,
          namedParameters,
          newNamedParameterTypes,
          newTypeVariables,
          typedefType);
    }
    return this;
  }

  FunctionType instantiate(List<DartType> arguments) {
    return subst(arguments, typeVariables);
  }

  @override
  R accept<R, A>(DartTypeVisitor<R, A> visitor, A argument) =>
      visitor.visitFunctionType(this, argument);

  int get hashCode {
    int hash = 3 * returnType.hashCode;
    for (DartType parameter in parameterTypes) {
      hash = 17 * hash + 5 * parameter.hashCode;
    }
    for (DartType parameter in optionalParameterTypes) {
      hash = 19 * hash + 7 * parameter.hashCode;
    }
    for (String name in namedParameters) {
      hash = 23 * hash + 11 * name.hashCode;
    }
    for (DartType parameter in namedParameterTypes) {
      hash = 29 * hash + 13 * parameter.hashCode;
    }
    return hash;
  }

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! FunctionType) return false;
    return _equalsInternal(other, null);
  }

  bool _equals(DartType other, _Assumptions assumptions) {
    if (identical(this, other)) return true;
    if (other is! FunctionType) return false;
    return _equalsInternal(other, assumptions);
  }

  bool _equalsInternal(FunctionType other, _Assumptions assumptions) {
    if (typeVariables.isNotEmpty) {
      if (typeVariables.length != other.typeVariables.length) return false;
      assumptions ??= new _Assumptions();
      for (int index = 0; index < typeVariables.length; index++) {
        assumptions.assume(typeVariables[index], other.typeVariables[index]);
      }
      for (int index = 0; index < typeVariables.length; index++) {
        if (!typeVariables[index]
            .bound
            ._equals(other.typeVariables[index].bound, assumptions)) {
          return false;
        }
      }
    }
    bool result = returnType == other.returnType &&
        _equalTypes(parameterTypes, other.parameterTypes, assumptions) &&
        _equalTypes(optionalParameterTypes, other.optionalParameterTypes,
            assumptions) &&
        equalElements(namedParameters, other.namedParameters) &&
        _equalTypes(
            namedParameterTypes, other.namedParameterTypes, assumptions);
    if (typeVariables.isNotEmpty) {
      for (int index = 0; index < typeVariables.length; index++) {
        assumptions.forget(typeVariables[index], other.typeVariables[index]);
      }
    }
    return result;
  }

  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write(returnType);
    sb.write(' Function');
    if (typeVariables.isNotEmpty) {
      sb.write('<');
      bool needsComma = false;
      for (FunctionTypeVariable typeVariable in typeVariables) {
        if (needsComma) {
          sb.write(',');
        }
        sb.write(typeVariable);
        DartType bound = typeVariable.bound;
        if (!bound.isObject) {
          sb.write(' extends ');
          sb.write(typeVariable.bound);
        }
        needsComma = true;
      }
      sb.write('>');
    }
    sb.write('(');
    bool needsComma = false;
    for (DartType parameterType in parameterTypes) {
      if (needsComma) {
        sb.write(',');
      }
      sb.write(parameterType);
      needsComma = true;
    }
    if (optionalParameterTypes.isNotEmpty) {
      if (needsComma) {
        sb.write(',');
      }
      sb.write('[');
      bool needsOptionalComma = false;
      for (DartType typeArgument in optionalParameterTypes) {
        if (needsOptionalComma) {
          sb.write(',');
        }
        sb.write(typeArgument);
        needsOptionalComma = true;
      }
      sb.write(']');
      needsComma = true;
    }
    if (namedParameters.isNotEmpty) {
      if (needsComma) {
        sb.write(',');
      }
      sb.write('{');
      bool needsNamedComma = false;
      for (int index = 0; index < namedParameters.length; index++) {
        if (needsNamedComma) {
          sb.write(',');
        }
        sb.write(namedParameterTypes[index]);
        sb.write(' ');
        sb.write(namedParameters[index]);
        needsNamedComma = true;
      }
      sb.write('}');
    }
    sb.write(')');
    return sb.toString();
  }
}

class FutureOrType extends DartType {
  final DartType typeArgument;

  FutureOrType(this.typeArgument);

  @override
  bool get isFutureOr => true;

  @override
  DartType subst(List<DartType> arguments, List<DartType> parameters) {
    DartType newTypeArgument = typeArgument.subst(arguments, parameters);
    if (identical(typeArgument, newTypeArgument)) return this;
    return new FutureOrType(newTypeArgument);
  }

  bool get containsTypeVariables => typeArgument.containsTypeVariables;

  void forEachTypeVariable(f(TypeVariableType variable)) {
    typeArgument.forEachTypeVariable(f);
  }

  R accept<R, A>(DartTypeVisitor<R, A> visitor, A argument) =>
      visitor.visitFutureOrType(this, argument);

  int get hashCode => typeArgument.hashCode * 13;

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! FutureOrType) return false;
    return _equalsInternal(other, null);
  }

  bool _equals(DartType other, _Assumptions assumptions) {
    if (identical(this, other)) return true;
    if (other is! FutureOrType) return false;
    return _equalsInternal(other, assumptions);
  }

  bool _equalsInternal(FutureOrType other, _Assumptions assumptions) {
    return typeArgument._equals(other.typeArgument, assumptions);
  }

  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write('FutureOr');
    sb.write('<');
    sb.write(typeArgument);
    sb.write('>');
    return sb.toString();
  }
}

/// Helper method for performing substitution of a list of types.
///
/// If no types are changed by the substitution, the [types] is returned
/// instead of a newly created list.
List<DartType> _substTypes(
    List<DartType> types, List<DartType> arguments, List<DartType> parameters) {
  bool changed = false;
  List<DartType> result =
      new List<DartType>.generate(types.length, (int index) {
    DartType type = types[index];
    DartType argument = type.subst(arguments, parameters);
    if (!changed && !identical(argument, type)) {
      changed = true;
    }
    return argument;
  });
  // Use the new List only if necessary.
  return changed ? result : types;
}

bool _equalTypes(List<DartType> a, List<DartType> b, _Assumptions assumptions) {
  if (a.length != b.length) return false;
  for (int index = 0; index < a.length; index++) {
    if (!a[index]._equals(b[index], assumptions)) {
      return false;
    }
  }
  return true;
}

abstract class DartTypeVisitor<R, A> {
  const DartTypeVisitor();

  R visit(covariant DartType type, A argument) => type.accept(this, argument);

  R visitVoidType(covariant VoidType type, A argument) => null;

  R visitTypeVariableType(covariant TypeVariableType type, A argument) => null;

  R visitFunctionTypeVariable(
          covariant FunctionTypeVariable type, A argument) =>
      null;

  R visitFunctionType(covariant FunctionType type, A argument) => null;

  R visitInterfaceType(covariant InterfaceType type, A argument) => null;

  R visitTypedefType(covariant TypedefType type, A argument) => null;

  R visitDynamicType(covariant DynamicType type, A argument) => null;

  R visitFutureOrType(covariant FutureOrType type, A argument) => null;
}

abstract class BaseDartTypeVisitor<R, A> extends DartTypeVisitor<R, A> {
  const BaseDartTypeVisitor();

  R visitType(covariant DartType type, A argument);

  @override
  R visitVoidType(covariant VoidType type, A argument) =>
      visitType(type, argument);

  @override
  R visitTypeVariableType(covariant TypeVariableType type, A argument) =>
      visitType(type, argument);

  @override
  R visitFunctionTypeVariable(
          covariant FunctionTypeVariable type, A argument) =>
      visitType(type, argument);

  @override
  R visitFunctionType(covariant FunctionType type, A argument) =>
      visitType(type, argument);

  @override
  R visitInterfaceType(covariant InterfaceType type, A argument) =>
      visitType(type, argument);

  @override
  R visitDynamicType(covariant DynamicType type, A argument) =>
      visitType(type, argument);

  @override
  R visitFutureOrType(covariant FutureOrType type, A argument) =>
      visitType(type, argument);
}

/// Abstract visitor for determining relations between types.
abstract class AbstractTypeRelation<T extends DartType>
    extends BaseDartTypeVisitor<bool, T> {
  CommonElements get commonElements;
  bool get strongMode;

  final _Assumptions assumptions = new _Assumptions();

  /// Ensures that the super hierarchy of [type] is computed.
  void ensureResolved(InterfaceType type) {}

  /// Returns the unaliased version of [type].
  T getUnaliased(T type) => type.unaliased;

  /// Returns [type] as an instance of [cls], or `null` if [type] is not subtype
  /// if [cls].
  InterfaceType asInstanceOf(InterfaceType type, ClassEntity cls);

  /// Returns the type of the `call` method on [type], or `null` if the class
  /// of [type] does not have a `call` method.
  FunctionType getCallType(InterfaceType type);

  /// Returns the declared bound of [element].
  DartType getTypeVariableBound(TypeVariableEntity element);

  bool visitType(T t, T s) {
    throw 'internal error: unknown type ${t}';
  }

  bool visitVoidType(VoidType t, T s) {
    assert(s is! VoidType);
    return false;
  }

  bool invalidTypeArguments(T t, T s);

  bool invalidFunctionReturnTypes(T t, T s);

  bool invalidFunctionParameterTypes(T t, T s);

  bool invalidTypeVariableBounds(T bound, T s);

  bool invalidCallableType(covariant DartType callType, covariant DartType s);

  bool visitInterfaceType(InterfaceType t, covariant DartType s) {
    ensureResolved(t);

    bool checkTypeArguments(InterfaceType instance, InterfaceType other) {
      List<T> tTypeArgs = instance.typeArguments;
      List<T> sTypeArgs = other.typeArguments;
      assert(tTypeArgs.length == sTypeArgs.length);
      for (int i = 0; i < tTypeArgs.length; i++) {
        if (invalidTypeArguments(tTypeArgs[i], sTypeArgs[i])) {
          return false;
        }
      }
      return true;
    }

    if (s is InterfaceType) {
      InterfaceType instance = asInstanceOf(t, s.element);
      if (instance != null && checkTypeArguments(instance, s)) {
        return true;
      }
    }

    FunctionType callType = getCallType(t);
    if (s == commonElements.functionType && callType != null) {
      return true;
    } else if (s is FunctionType) {
      return callType != null && !invalidCallableType(callType, s);
    }

    return false;
  }

  bool visitFunctionType(FunctionType t, DartType s) {
    if (s == commonElements.functionType) {
      return true;
    }
    if (s is! FunctionType) return false;
    FunctionType tf = t;
    FunctionType sf = s;
    if (invalidFunctionReturnTypes(tf.returnType, sf.returnType)) {
      return false;
    }

    if (tf.typeVariables.length != sf.typeVariables.length) {
      return false;
    }
    for (int i = 0; i < tf.typeVariables.length; i++) {
      assumptions.assume(tf.typeVariables[i], sf.typeVariables[i]);
    }
    for (int i = 0; i < tf.typeVariables.length; i++) {
      if (!tf.typeVariables[i].bound
          ._equals(sf.typeVariables[i].bound, assumptions)) {
        return false;
      }
    }
    bool result = visitFunctionTypeInternal(tf, sf);
    for (int i = 0; i < tf.typeVariables.length; i++) {
      assumptions.forget(tf.typeVariables[i], sf.typeVariables[i]);
    }
    return result;
  }

  bool visitFunctionTypeInternal(FunctionType tf, FunctionType sf) {
    // TODO(johnniwinther): Rewrite the function subtyping to be more readable
    // but still as efficient.

    // For the comments we use the following abbreviations:
    //  x.p     : parameterTypes on [:x:],
    //  x.o     : optionalParameterTypes on [:x:], and
    //  len(xs) : length of list [:xs:].

    Iterator<T> tps = tf.parameterTypes.iterator;
    Iterator<T> sps = sf.parameterTypes.iterator;
    bool sNotEmpty = sps.moveNext();
    bool tNotEmpty = tps.moveNext();
    tNext() => (tNotEmpty = tps.moveNext());
    sNext() => (sNotEmpty = sps.moveNext());

    bool incompatibleParameters() {
      while (tNotEmpty && sNotEmpty) {
        if (invalidFunctionParameterTypes(tps.current, sps.current)) {
          return true;
        }
        tNext();
        sNext();
      }
      return false;
    }

    if (incompatibleParameters()) return false;
    if (tNotEmpty) {
      // We must have [: len(t.p) <= len(s.p) :].
      return false;
    }
    if (!sf.namedParameters.isEmpty) {
      // We must have [: len(t.p) == len(s.p) :].
      if (sNotEmpty) {
        return false;
      }
      // Since named parameters are globally ordered we can determine the
      // subset relation with a linear search for [:sf.namedParameters:]
      // within [:tf.namedParameters:].
      List<String> tNames = tf.namedParameters;
      List<T> tTypes = tf.namedParameterTypes;
      List<String> sNames = sf.namedParameters;
      List<T> sTypes = sf.namedParameterTypes;
      int tIndex = 0;
      int sIndex = 0;
      while (tIndex < tNames.length && sIndex < sNames.length) {
        if (tNames[tIndex] == sNames[sIndex]) {
          if (invalidFunctionParameterTypes(tTypes[tIndex], sTypes[sIndex])) {
            return false;
          }
          sIndex++;
        }
        tIndex++;
      }
      if (sIndex < sNames.length) {
        // We didn't find all names.
        return false;
      }
    } else {
      // Check the remaining [: s.p :] against [: t.o :].
      tps = tf.optionalParameterTypes.iterator;
      tNext();
      if (incompatibleParameters()) return false;
      if (sNotEmpty) {
        // We must have [: len(t.p) + len(t.o) >= len(s.p) :].
        return false;
      }
      if (!sf.optionalParameterTypes.isEmpty) {
        // Check the remaining [: s.o :] against the remaining [: t.o :].
        sps = sf.optionalParameterTypes.iterator;
        sNext();
        if (incompatibleParameters()) return false;
        if (sNotEmpty) {
          // We didn't find enough parameters:
          // We must have [: len(t.p) + len(t.o) <= len(s.p) + len(s.o) :].
          return false;
        }
      } else {
        if (sNotEmpty) {
          // We must have [: len(t.p) + len(t.o) >= len(s.p) :].
          return false;
        }
      }
    }
    return true;
  }

  bool visitTypeVariableType(TypeVariableType t, T s) {
    // Identity check is handled in [isSubtype].
    DartType bound = getTypeVariableBound(t.element);
    if (bound.isTypeVariable) {
      // The bound is potentially cyclic so we need to be extra careful.
      Set<TypeVariableEntity> seenTypeVariables = new Set<TypeVariableEntity>();
      seenTypeVariables.add(t.element);
      while (bound.isTypeVariable) {
        TypeVariableType typeVariable = bound;
        if (bound == s) {
          // [t] extends [s].
          return true;
        }
        if (seenTypeVariables.contains(typeVariable.element)) {
          // We have a cycle and have already checked all bounds in the cycle
          // against [s] and can therefore conclude that [t] is not a subtype
          // of [s].
          return false;
        }
        seenTypeVariables.add(typeVariable.element);
        bound = getTypeVariableBound(typeVariable.element);
      }
    }
    if (invalidTypeVariableBounds(bound, s)) return false;
    return true;
  }

  bool visitFunctionTypeVariable(FunctionTypeVariable t, DartType s) {
    if (!s.isFunctionTypeVariable) return false;
    return assumptions.isAssumed(t, s);
  }
}

abstract class MoreSpecificVisitor<T extends DartType>
    extends AbstractTypeRelation<T> {
  bool isMoreSpecific(T t, T s) {
    if (strongMode) {
      if (identical(t, s) ||
          s.treatAsDynamic ||
          s.isVoid ||
          s == commonElements.objectType ||
          t == commonElements.nullType) {
        return true;
      }
      if (t.treatAsDynamic) {
        return false;
      }
    } else {
      if (identical(t, s) || s.treatAsDynamic || t == commonElements.nullType) {
        return true;
      }
      if (t.isVoid || s.isVoid) {
        return false;
      }
      if (t.treatAsDynamic) {
        return false;
      }
      if (s == commonElements.objectType) {
        return true;
      }
    }

    t = getUnaliased(t);
    s = getUnaliased(s);

    return t.accept(this, s);
  }

  bool invalidTypeArguments(T t, T s) {
    return !isMoreSpecific(t, s);
  }

  bool invalidFunctionReturnTypes(T t, T s) {
    if (s.treatAsDynamic && t.isVoid) return true;
    return !s.isVoid && !isMoreSpecific(t, s);
  }

  bool invalidFunctionParameterTypes(T t, T s) {
    return !isMoreSpecific(t, s);
  }

  bool invalidTypeVariableBounds(T bound, T s) {
    return !isMoreSpecific(bound, s);
  }

  bool invalidCallableType(covariant DartType callType, covariant DartType s) {
    return !isMoreSpecific(callType, s);
  }

  bool visitFutureOrType(FutureOrType t, covariant DartType s) {
    return false;
  }
}

/// Type visitor that determines the subtype relation two types.
abstract class SubtypeVisitor<T extends DartType>
    extends MoreSpecificVisitor<T> {
  bool isSubtype(DartType t, DartType s) {
    if (!strongMode && t.treatAsDynamic) {
      return true;
    }
    if (s.isFutureOr) {
      FutureOrType sFutureOr = s;
      if (isSubtype(t, sFutureOr.typeArgument)) {
        return true;
      } else if (t.isInterfaceType) {
        InterfaceType tInterface = t;
        if (tInterface.element == commonElements.futureClass &&
            isSubtype(
                tInterface.typeArguments.single, sFutureOr.typeArgument)) {
          return true;
        }
      }
    }
    return isMoreSpecific(t, s);
  }

  bool isAssignable(T t, T s) {
    return isSubtype(t, s) || isSubtype(s, t);
  }

  bool invalidTypeArguments(T t, T s) {
    return !isSubtype(t, s);
  }

  bool invalidFunctionReturnTypes(T t, T s) {
    if (strongMode) return !isSubtype(t, s);
    return !s.isVoid && !isAssignable(t, s);
  }

  bool invalidFunctionParameterTypes(T t, T s) {
    if (strongMode) return !isSubtype(s, t);
    return !isAssignable(t, s);
  }

  bool invalidTypeVariableBounds(T bound, T s) {
    return !isSubtype(bound, s);
  }

  bool invalidCallableType(covariant DartType callType, covariant DartType s) {
    return !isSubtype(callType, s);
  }

  bool visitFutureOrType(FutureOrType t, covariant DartType s) {
    if (s.isFutureOr) {
      FutureOrType sFutureOr = s;
      return isSubtype(t.typeArgument, sFutureOr.typeArgument);
    }
    return false;
  }
}

/// Type visitor that determines one type could a subtype of another given the
/// right type variable substitution. The computation is approximate and returns
/// `false` only if we are sure no such substitution exists.
abstract class PotentialSubtypeVisitor<T extends DartType>
    extends SubtypeVisitor<T> {
  bool isSubtype(DartType t, DartType s) {
    if (t is TypeVariableType || s is TypeVariableType) {
      return true;
    }
    return super.isSubtype(t, s);
  }
}

/// Basic interface for the Dart type system.
abstract class DartTypes {
  /// The types defined in 'dart:core'.
  CommonElements get commonElements;

  /// Returns `true` if [t] is a subtype of [s].
  bool isSubtype(DartType t, DartType s);

  /// Returns `true` if [t] is assignable to [s].
  bool isAssignable(DartType t, DartType s);

  /// Returns `true` if [t] might be a subtype of [s] for some values of
  /// type variables in [s] and [t].
  bool isPotentialSubtype(DartType t, DartType s);

  static const int IS_SUBTYPE = 1;
  static const int MAYBE_SUBTYPE = 0;
  static const int NOT_SUBTYPE = -1;

  /// Returns [IS_SUBTYPE], [MAYBE_SUBTYPE], or [NOT_SUBTYPE] if [t] is a
  /// (potential) subtype of [s]
  int computeSubtypeRelation(DartType t, DartType s) {
    // TODO(johnniwinther): Compute this directly in [isPotentialSubtype].
    if (isSubtype(t, s)) return IS_SUBTYPE;
    return isPotentialSubtype(t, s) ? MAYBE_SUBTYPE : NOT_SUBTYPE;
  }

  /// Returns [type] as an instance of [cls] or `null` if [type] is not a
  /// subtype of [cls].
  ///
  /// For example: `asInstanceOf(List<String>, Iterable) = Iterable<String>`.
  InterfaceType asInstanceOf(InterfaceType type, ClassEntity cls);

  /// Return [base] where the type variable of `context.element` are replaced
  /// by the type arguments of [context].
  ///
  /// For instance
  ///
  ///     substByContext(Iterable<List.E>, List<String>) = Iterable<String>
  ///
  DartType substByContext(DartType base, InterfaceType context);

  /// Returns the 'this type' of [cls]. That is, the instantiation of [cls]
  /// where the type arguments are the type variables of [cls].
  InterfaceType getThisType(ClassEntity cls);

  /// Returns the supertype of [cls], i.e. the type in the `extends` clause of
  /// [cls].
  InterfaceType getSupertype(ClassEntity cls);

  /// Returns all supertypes of [cls].
  // TODO(johnniwinther): This should include `Function` if [cls] declares
  // a `call` method.
  Iterable<InterfaceType> getSupertypes(ClassEntity cls);

  /// Returns all types directly implemented by [cls].
  Iterable<InterfaceType> getInterfaces(ClassEntity cls);

  /// Returns the type of the `call` method on [type], or `null` if the class
  /// of [type] does not have a `call` method.
  FunctionType getCallType(InterfaceType type);

  /// Checks the type arguments of [type] against the type variable bounds
  /// declared on `type.element`. Calls [checkTypeVariableBound] on each type
  /// argument and bound.
  void checkTypeVariableBounds(
      InterfaceType type,
      void checkTypeVariableBound(InterfaceType type, DartType typeArgument,
          TypeVariableType typeVariable, DartType bound));

  /// Returns the [ClassEntity] which declares the type variables occurring in
  // [type], or `null` if [type] does not contain class type variables.
  static ClassEntity getClassContext(DartType type) {
    ClassEntity contextClass;
    type.forEachTypeVariable((TypeVariableType typeVariable) {
      if (typeVariable.element.typeDeclaration is! ClassEntity) return;
      contextClass = typeVariable.element.typeDeclaration;
    });
    // GENERIC_METHODS: When generic method support is complete enough to
    // include a runtime value for method type variables this must be updated.
    // For full support the global assumption that all type variables are
    // declared by the same enclosing class will not hold: Both an enclosing
    // method and an enclosing class may define type variables, so the return
    // type cannot be [ClassElement] and the caller must be prepared to look in
    // two locations, not one. Currently we ignore method type variables by
    // returning in the next statement.
    return contextClass;
  }
}
