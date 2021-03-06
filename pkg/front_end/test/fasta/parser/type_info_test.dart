// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:front_end/src/fasta/messages.dart';
import 'package:front_end/src/fasta/parser.dart';
import 'package:front_end/src/fasta/parser/type_info.dart';
import 'package:front_end/src/fasta/scanner.dart';
import 'package:front_end/src/scanner/token.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(TokenInfoTest);
  });
}

@reflectiveTest
class TokenInfoTest {
  void test_noType() {
    TypeInfo typeInfo = noTypeInfo;
    Token start = scanString('before ;').tokens;
    Token expectedEnd = start;
    expect(typeInfo.couldBeExpression, isFalse);
    expect(typeInfo.skipType(start), expectedEnd);

    TypeInfoListener listener = new TypeInfoListener();
    expect(typeInfo.ensureTypeNotVoid(start, new Parser(listener)),
        new isInstanceOf<SyntheticStringToken>());
    expect(listener.calls, [
      'handleIdentifier  typeReference',
      'handleNoTypeArguments ;',
      'handleType  ;',
    ]);
    expect(listener.errors, [new ExpectedError(codeExpectedType, 7, 1)]);

    listener = new TypeInfoListener();
    expect(typeInfo.parseTypeNotVoid(start, new Parser(listener)), expectedEnd);
    expect(listener.calls, ['handleNoType before']);
    expect(listener.errors, isNull);

    listener = new TypeInfoListener();
    expect(typeInfo.parseType(start, new Parser(listener)), expectedEnd);
    expect(listener.calls, ['handleNoType before']);
    expect(listener.errors, isNull);
  }

  void test_voidType() {
    TypeInfo typeInfo = voidTypeInfo;
    Token start = scanString('before void ;').tokens;
    Token expectedEnd = start.next;
    expect(typeInfo.skipType(start), expectedEnd);
    expect(typeInfo.couldBeExpression, isFalse);

    TypeInfoListener listener = new TypeInfoListener();
    expect(
        typeInfo.ensureTypeNotVoid(start, new Parser(listener)), expectedEnd);
    expect(listener.calls, [
      'handleIdentifier void typeReference',
      'handleNoTypeArguments ;',
      'handleType void ;',
    ]);
    expect(listener.errors, [new ExpectedError(codeInvalidVoid, 7, 4)]);

    listener = new TypeInfoListener();
    expect(typeInfo.parseTypeNotVoid(start, new Parser(listener)), expectedEnd);
    expect(listener.calls, [
      'handleIdentifier void typeReference',
      'handleNoTypeArguments ;',
      'handleType void ;',
    ]);
    expect(listener.errors, [new ExpectedError(codeInvalidVoid, 7, 4)]);

    listener = new TypeInfoListener();
    expect(typeInfo.parseType(start, new Parser(listener)), expectedEnd);
    expect(listener.calls, ['handleVoidKeyword void']);
    expect(listener.errors, isNull);
  }

  void test_prefixedTypeInfo() {
    TypeInfo typeInfo = prefixedTypeInfo;
    Token start = scanString('before C.a ;').tokens;
    Token expectedEnd = start.next.next.next;
    expect(typeInfo.skipType(start), expectedEnd);
    expect(typeInfo.couldBeExpression, isTrue);

    TypeInfoListener listener;
    assertResult(Token actualEnd) {
      expect(actualEnd, expectedEnd);
      expect(listener.calls, [
        'handleIdentifier C prefixedTypeReference',
        'handleIdentifier a typeReferenceContinuation',
        'handleQualified .',
        'handleNoTypeArguments ;',
        'handleType C ;',
      ]);
      expect(listener.errors, isNull);
    }

    listener = new TypeInfoListener();
    assertResult(typeInfo.ensureTypeNotVoid(start, new Parser(listener)));

    listener = new TypeInfoListener();
    assertResult(typeInfo.parseTypeNotVoid(start, new Parser(listener)));

    listener = new TypeInfoListener();
    assertResult(typeInfo.parseType(start, new Parser(listener)));
  }

  void test_simpleTypeInfo() {
    TypeInfo typeInfo = simpleTypeInfo;
    Token start = scanString('before C ;').tokens;
    Token expectedEnd = start.next;
    expect(typeInfo.skipType(start), expectedEnd);
    expect(typeInfo.couldBeExpression, isTrue);

    TypeInfoListener listener;
    assertResult(Token actualEnd) {
      expect(actualEnd, expectedEnd);
      expect(listener.calls, [
        'handleIdentifier C typeReference',
        'handleNoTypeArguments ;',
        'handleType C ;',
      ]);
      expect(listener.errors, isNull);
    }

    listener = new TypeInfoListener();
    assertResult(typeInfo.ensureTypeNotVoid(start, new Parser(listener)));

    listener = new TypeInfoListener();
    assertResult(typeInfo.parseTypeNotVoid(start, new Parser(listener)));

    listener = new TypeInfoListener();
    assertResult(typeInfo.parseType(start, new Parser(listener)));
  }

  void test_simpleTypeArgumentsInfo() {
    TypeInfo typeInfo = simpleTypeArgumentsInfo;
    Token start = scanString('before C<T> ;').tokens;
    Token expectedEnd = start.next.next.next.next;
    expect(typeInfo.skipType(start), expectedEnd);
    expect(typeInfo.couldBeExpression, isFalse);

    TypeInfoListener listener;
    assertResult(Token actualEnd) {
      expect(actualEnd, expectedEnd);
      expect(listener.calls, [
        'handleIdentifier C typeReference',
        'beginTypeArguments <',
        'handleIdentifier T typeReference',
        'handleNoTypeArguments >',
        'handleType T >',
        'endTypeArguments 1 < >',
        'handleType C ;',
      ]);
      expect(listener.errors, isNull);
    }

    listener = new TypeInfoListener();
    assertResult(typeInfo.ensureTypeNotVoid(start, new Parser(listener)));

    listener = new TypeInfoListener();
    assertResult(typeInfo.parseTypeNotVoid(start, new Parser(listener)));

    listener = new TypeInfoListener();
    assertResult(typeInfo.parseType(start, new Parser(listener)));
  }

  void test_computeType_basic() {
    expectInfo(noTypeInfo, '');
    expectInfo(noTypeInfo, ';');
    expectInfo(noTypeInfo, '( foo');
    expectInfo(noTypeInfo, '< foo');
    expectInfo(noTypeInfo, '= foo');
    expectInfo(noTypeInfo, '* foo');
    expectInfo(noTypeInfo, 'do foo');
    expectInfo(noTypeInfo, 'get foo');
    expectInfo(noTypeInfo, 'set foo');
    expectInfo(noTypeInfo, 'operator *');
  }

  void test_computeType_builtin() {
    // Expect complex rather than simpleTypeInfo so that parseType reports
    // an error for the builtin used as a type.
    expectComplexInfo('abstract',
        required: true,
        expectedErrors: [error(codeBuiltInIdentifierAsType, 0, 8)]);
    expectComplexInfo('export',
        required: true,
        expectedErrors: [error(codeBuiltInIdentifierAsType, 0, 6)]);
    expectComplexInfo('abstract Function()',
        required: false,
        tokenAfter: 'Function',
        expectedErrors: [error(codeBuiltInIdentifierAsType, 0, 8)]);
    expectComplexInfo('export Function()',
        required: false,
        tokenAfter: 'Function',
        expectedErrors: [error(codeBuiltInIdentifierAsType, 0, 6)]);
  }

  void test_computeType_gft() {
    expectComplexInfo('Function() m', tokenAfter: 'm', expectedCalls: [
      'handleNoTypeVariables (',
      'beginFunctionType Function',
      'handleNoType ',
      'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
      'endFormalParameters 0 ( ) MemberKind.GeneralizedFunctionType',
      'endFunctionType Function m',
    ]);
    expectComplexInfo('Function<T>() m', tokenAfter: 'm', expectedCalls: [
      'beginTypeVariables <',
      'beginTypeVariable T',
      'beginMetadataStar T',
      'endMetadataStar 0',
      'handleIdentifier T typeVariableDeclaration',
      'handleNoType T',
      'endTypeVariable > null',
      'endTypeVariables 1 < >',
      'beginFunctionType Function',
      'handleNoType ',
      'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
      'endFormalParameters 0 ( ) MemberKind.GeneralizedFunctionType',
      'endFunctionType Function m',
    ]);
    expectComplexInfo('Function(int) m', tokenAfter: 'm', expectedCalls: [
      'handleNoTypeVariables (',
      'beginFunctionType Function',
      'handleNoType ',
      'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
      'beginMetadataStar int',
      'endMetadataStar 0',
      'beginFormalParameter int MemberKind.GeneralizedFunctionType',
      'handleModifiers 0',
      'handleIdentifier int typeReference',
      'handleNoTypeArguments )',
      'handleType int )',
      'handleNoName )',
      'handleFormalParameterWithoutValue )',
      'beginTypeVariables null null ) FormalParameterKind.mandatory '
          'MemberKind.GeneralizedFunctionType',
      'endFormalParameters 1 ( ) MemberKind.GeneralizedFunctionType',
      'endFunctionType Function m',
    ]);
    expectComplexInfo('Function<T>(int) m', tokenAfter: 'm', expectedCalls: [
      'beginTypeVariables <',
      'beginTypeVariable T',
      'beginMetadataStar T',
      'endMetadataStar 0',
      'handleIdentifier T typeVariableDeclaration',
      'handleNoType T',
      'endTypeVariable > null',
      'endTypeVariables 1 < >',
      'beginFunctionType Function',
      'handleNoType ',
      'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
      'beginMetadataStar int',
      'endMetadataStar 0',
      'beginFormalParameter int MemberKind.GeneralizedFunctionType',
      'handleModifiers 0',
      'handleIdentifier int typeReference',
      'handleNoTypeArguments )',
      'handleType int )',
      'handleNoName )',
      'handleFormalParameterWithoutValue )',
      'beginTypeVariables null null ) FormalParameterKind.mandatory MemberKind.GeneralizedFunctionType',
      'endFormalParameters 1 ( ) MemberKind.GeneralizedFunctionType',
      'endFunctionType Function m',
    ]);

    expectInfo(noTypeInfo, 'Function(int x)', required: false);
    expectInfo(noTypeInfo, 'Function<T>(int x)', required: false);

    expectComplexInfo('Function(int x)', required: true);
    expectComplexInfo('Function<T>(int x)', required: true);

    expectComplexInfo('Function(int x) m', tokenAfter: 'm');
    expectComplexInfo('Function<T>(int x) m', tokenAfter: 'm');
    expectComplexInfo('Function<T>(int x) Function<T>(int x)',
        required: false, tokenAfter: 'Function');
    expectComplexInfo('Function<T>(int x) Function<T>(int x)', required: true);
    expectComplexInfo('Function<T>(int x) Function<T>(int x) m',
        tokenAfter: 'm');
  }

  void test_computeType_identifier() {
    expectInfo(noTypeInfo, 'C', required: false);
    expectInfo(noTypeInfo, 'C;', required: false);
    expectInfo(noTypeInfo, 'C(', required: false);
    expectInfo(noTypeInfo, 'C<', required: false);
    expectInfo(noTypeInfo, 'C.', required: false);
    expectInfo(noTypeInfo, 'C=', required: false);
    expectInfo(noTypeInfo, 'C*', required: false);
    expectInfo(noTypeInfo, 'C do', required: false);

    expectInfo(simpleTypeInfo, 'C', required: true);
    expectInfo(simpleTypeInfo, 'C;', required: true);
    expectInfo(simpleTypeInfo, 'C(', required: true);
    expectInfo(simpleTypeInfo, 'C<', required: true);
    expectInfo(simpleTypeInfo, 'C.', required: true);
    expectInfo(simpleTypeInfo, 'C=', required: true);
    expectInfo(simpleTypeInfo, 'C*', required: true);
    expectInfo(simpleTypeInfo, 'C do', required: true);

    expectInfo(simpleTypeInfo, 'C foo');
    expectInfo(simpleTypeInfo, 'C get');
    expectInfo(simpleTypeInfo, 'C set');
    expectInfo(simpleTypeInfo, 'C operator');
    expectInfo(simpleTypeInfo, 'C this');
    expectInfo(simpleTypeInfo, 'C Function');
  }

  void test_computeType_identifierComplex() {
    expectInfo(simpleTypeInfo, 'C Function()', required: false);
    expectInfo(simpleTypeInfo, 'C Function<T>()', required: false);
    expectInfo(simpleTypeInfo, 'C Function(int)', required: false);
    expectInfo(simpleTypeInfo, 'C Function<T>(int)', required: false);
    expectInfo(simpleTypeInfo, 'C Function(int x)', required: false);
    expectInfo(simpleTypeInfo, 'C Function<T>(int x)', required: false);

    expectComplexInfo('C Function()', required: true);
    expectComplexInfo('C Function<T>()', required: true);
    expectComplexInfo('C Function(int)', required: true);
    expectComplexInfo('C Function<T>(int)', required: true);
    expectComplexInfo('C Function(int x)', required: true);
    expectComplexInfo('C Function<T>(int x)', required: true);
    expectComplexInfo('C Function<T>(int x) Function<T>(int x)',
        required: false, tokenAfter: 'Function');
    expectComplexInfo('C Function<T>(int x) Function<T>(int x)',
        required: true);
    expectComplexInfo('C Function(', // Scanner inserts synthetic ')'.
        required: true,
        expectedCalls: [
          'handleNoTypeVariables (',
          'beginFunctionType C',
          'handleIdentifier C typeReference',
          'handleNoTypeArguments Function',
          'handleType C Function',
          'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
          'endFormalParameters 0 ( ) MemberKind.GeneralizedFunctionType',
          'endFunctionType Function ',
        ]);
  }

  void test_computeType_identifierTypeArg() {
    expectInfo(noTypeInfo, 'C<T>', required: false);
    expectInfo(noTypeInfo, 'C<T>;', required: false);
    expectInfo(noTypeInfo, 'C<T>(', required: false);
    expectInfo(noTypeInfo, 'C<T> do', required: false);
    expectInfo(noTypeInfo, 'C<void>', required: false);

    expectInfo(simpleTypeArgumentsInfo, 'C<T>', required: true);
    expectInfo(simpleTypeArgumentsInfo, 'C<T>;', required: true);
    expectInfo(simpleTypeArgumentsInfo, 'C<T>(', required: true);
    expectInfo(simpleTypeArgumentsInfo, 'C<T> do', required: true);
    expectComplexInfo('C<void>', required: true, expectedCalls: [
      'handleIdentifier C typeReference',
      'beginTypeArguments <',
      'handleVoidKeyword void',
      'endTypeArguments 1 < >',
      'handleType C ',
    ]);

    expectInfo(simpleTypeArgumentsInfo, 'C<T> foo');
    expectInfo(simpleTypeArgumentsInfo, 'C<T> get');
    expectInfo(simpleTypeArgumentsInfo, 'C<T> set');
    expectInfo(simpleTypeArgumentsInfo, 'C<T> operator');
    expectInfo(simpleTypeArgumentsInfo, 'C<T> Function');
  }

  void test_computeType_identifierTypeArgComplex() {
    expectInfo(noTypeInfo, 'C<S,T>', required: false);
    expectInfo(noTypeInfo, 'C<S<T>>', required: false);
    expectInfo(noTypeInfo, 'C.a<T>', required: false);

    expectComplexInfo('C<S,T>', required: true, expectedCalls: [
      'handleIdentifier C typeReference',
      'beginTypeArguments <',
      'handleIdentifier S typeReference',
      'handleNoTypeArguments ,',
      'handleType S ,',
      'handleIdentifier T typeReference',
      'handleNoTypeArguments >',
      'handleType T >',
      'endTypeArguments 2 < >',
      'handleType C ',
    ]);
    expectComplexInfo('C<S<T>>', required: true, expectedCalls: [
      'handleIdentifier C typeReference',
      'beginTypeArguments <',
      'handleIdentifier S typeReference',
      'beginTypeArguments <',
      'handleIdentifier T typeReference',
      'handleNoTypeArguments >',
      'handleType T >',
      'endTypeArguments 1 < >',
      'handleType S >',
      'endTypeArguments 1 < >',
      'handleType C ',
    ]);
    expectComplexInfo('C<S,T> f', tokenAfter: 'f', expectedCalls: [
      'handleIdentifier C typeReference',
      'beginTypeArguments <',
      'handleIdentifier S typeReference',
      'handleNoTypeArguments ,',
      'handleType S ,',
      'handleIdentifier T typeReference',
      'handleNoTypeArguments >',
      'handleType T >',
      'endTypeArguments 2 < >',
      'handleType C f',
    ]);
    expectComplexInfo('C<S<T>> f', tokenAfter: 'f', expectedCalls: [
      'handleIdentifier C typeReference',
      'beginTypeArguments <',
      'handleIdentifier S typeReference',
      'beginTypeArguments <',
      'handleIdentifier T typeReference',
      'handleNoTypeArguments >',
      'handleType T >',
      'endTypeArguments 1 < >',
      'handleType S >',
      'endTypeArguments 1 < >',
      'handleType C f',
    ]);
  }

  void test_computeType_identifierTypeArgGFT() {
    expectComplexInfo('C<T> Function(', // Scanner inserts synthetic ')'.
        required: true,
        expectedCalls: [
          'handleNoTypeVariables (',
          'beginFunctionType C',
          'handleIdentifier C typeReference',
          'beginTypeArguments <',
          'handleIdentifier T typeReference',
          'handleNoTypeArguments >',
          'handleType T >',
          'endTypeArguments 1 < >',
          'handleType C Function',
          'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
          'endFormalParameters 0 ( ) MemberKind.GeneralizedFunctionType',
          'endFunctionType Function ',
        ]);
    expectComplexInfo('C<T> Function<T>(int x) Function<T>(int x)',
        required: false, tokenAfter: 'Function');
    expectComplexInfo('C<T> Function<T>(int x) Function<T>(int x)',
        required: true);
  }

  void test_computeType_identifierTypeArgRecovery() {
    // TOOD(danrubel): dynamic, do, other keywords, malformed, recovery
    // <T>

    expectComplexInfo('G<int double> g',
        required: true,
        tokenAfter: 'g',
        expectedCalls: [
          'handleIdentifier G typeReference',
          'beginTypeArguments <',
          'handleIdentifier int typeReference',
          'handleNoTypeArguments double',
          'handleType int double',
          'endTypeArguments 1 < >',
          'handleType G g',
        ],
        expectedErrors: [
          error(codeExpectedToken, 6, 6)
        ]);

    expectInfo(noTypeInfo, 'C<>', required: false);
    expectComplexInfo('C<>', required: true, expectedCalls: [
      'handleIdentifier C typeReference',
      'beginTypeArguments <',
      'handleIdentifier  typeReference',
      'handleNoTypeArguments >',
      'handleType > >',
      'endTypeArguments 1 < >',
      'handleType C ',
    ], expectedErrors: [
      error(codeExpectedType, 2, 1)
    ]);
    expectComplexInfo('C<> f', required: true, tokenAfter: 'f', expectedCalls: [
      'handleIdentifier C typeReference',
      'beginTypeArguments <',
      'handleIdentifier  typeReference',
      'handleNoTypeArguments >',
      'handleType > >',
      'endTypeArguments 1 < >',
      'handleType C f',
    ], expectedErrors: [
      error(codeExpectedType, 2, 1)
    ]);

    // Statements that should not have a type
    expectInfo(noTypeInfo, 'C<T ; T>U;', required: false);
    expectInfo(noTypeInfo, 'C<T && T>U;', required: false);
  }

  void test_computeType_prefixed() {
    expectInfo(noTypeInfo, 'C.a', required: false);
    expectInfo(noTypeInfo, 'C.a;', required: false);
    expectInfo(noTypeInfo, 'C.a(', required: false);
    expectInfo(noTypeInfo, 'C.a<', required: false);
    expectInfo(noTypeInfo, 'C.a=', required: false);
    expectInfo(noTypeInfo, 'C.a*', required: false);
    expectInfo(noTypeInfo, 'C.a do', required: false);

    expectInfo(prefixedTypeInfo, 'C.a', required: true);
    expectInfo(prefixedTypeInfo, 'C.a;', required: true);
    expectInfo(prefixedTypeInfo, 'C.a(', required: true);
    expectInfo(prefixedTypeInfo, 'C.a<', required: true);
    expectInfo(prefixedTypeInfo, 'C.a=', required: true);
    expectInfo(prefixedTypeInfo, 'C.a*', required: true);
    expectInfo(prefixedTypeInfo, 'C.a do', required: true);

    expectInfo(prefixedTypeInfo, 'C.a foo');
    expectInfo(prefixedTypeInfo, 'C.a get');
    expectInfo(prefixedTypeInfo, 'C.a set');
    expectInfo(prefixedTypeInfo, 'C.a operator');
    expectInfo(prefixedTypeInfo, 'C.a Function');
  }

  void test_computeType_prefixedGFT() {
    expectComplexInfo('C.a Function(', // Scanner inserts synthetic ')'.
        required: true,
        expectedCalls: [
          'handleNoTypeVariables (',
          'beginFunctionType C',
          'handleIdentifier C prefixedTypeReference',
          'handleIdentifier a typeReferenceContinuation',
          'handleQualified .',
          'handleNoTypeArguments Function',
          'handleType C Function',
          'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
          'endFormalParameters 0 ( ) MemberKind.GeneralizedFunctionType',
          'endFunctionType Function ',
        ]);
    expectComplexInfo('C.a Function<T>(int x) Function<T>(int x)',
        required: false, tokenAfter: 'Function');
    expectComplexInfo('C.a Function<T>(int x) Function<T>(int x)',
        required: true);
  }

  void test_computeType_prefixedTypeArg() {
    expectComplexInfo('C.a<T>', required: true, expectedCalls: [
      'handleIdentifier C prefixedTypeReference',
      'handleIdentifier a typeReferenceContinuation',
      'handleQualified .',
      'beginTypeArguments <',
      'handleIdentifier T typeReference',
      'handleNoTypeArguments >',
      'handleType T >',
      'endTypeArguments 1 < >',
      'handleType C ',
    ]);

    expectComplexInfo('C.a<T> f', tokenAfter: 'f', expectedCalls: [
      'handleIdentifier C prefixedTypeReference',
      'handleIdentifier a typeReferenceContinuation',
      'handleQualified .',
      'beginTypeArguments <',
      'handleIdentifier T typeReference',
      'handleNoTypeArguments >',
      'handleType T >',
      'endTypeArguments 1 < >',
      'handleType C f',
    ]);
  }

  void test_computeType_prefixedTypeArgGFT() {
    expectComplexInfo('C.a<T> Function<T>(int x) Function<T>(int x)',
        required: true,
        expectedCalls: [
          'beginTypeVariables <',
          'beginTypeVariable T',
          'beginMetadataStar T',
          'endMetadataStar 0',
          'handleIdentifier T typeVariableDeclaration',
          'handleNoType T',
          'endTypeVariable > null',
          'endTypeVariables 1 < >',
          'beginFunctionType C',
          'beginTypeVariables <',
          'beginTypeVariable T',
          'beginMetadataStar T',
          'endMetadataStar 0',
          'handleIdentifier T typeVariableDeclaration',
          'handleNoType T',
          'endTypeVariable > null',
          'endTypeVariables 1 < >',
          'beginFunctionType C',
          'handleIdentifier C prefixedTypeReference',
          'handleIdentifier a typeReferenceContinuation',
          'handleQualified .',
          'beginTypeArguments <',
          'handleIdentifier T typeReference',
          'handleNoTypeArguments >',
          'handleType T >',
          'endTypeArguments 1 < >',
          'handleType C Function',
          'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
          'beginMetadataStar int',
          'endMetadataStar 0',
          'beginFormalParameter int MemberKind.GeneralizedFunctionType',
          'handleModifiers 0',
          'handleIdentifier int typeReference',
          'handleNoTypeArguments x',
          'handleType int x',
          'handleIdentifier x formalParameterDeclaration',
          'handleFormalParameterWithoutValue )',
          'beginTypeVariables null null x FormalParameterKind.mandatory '
              'MemberKind.GeneralizedFunctionType',
          'endFormalParameters 1 ( ) MemberKind.GeneralizedFunctionType',
          'endFunctionType Function Function',
          'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
          'beginMetadataStar int',
          'endMetadataStar 0',
          'beginFormalParameter int MemberKind.GeneralizedFunctionType',
          'handleModifiers 0',
          'handleIdentifier int typeReference',
          'handleNoTypeArguments x',
          'handleType int x',
          'handleIdentifier x formalParameterDeclaration',
          'handleFormalParameterWithoutValue )',
          'beginTypeVariables null null x FormalParameterKind.mandatory '
              'MemberKind.GeneralizedFunctionType',
          'endFormalParameters 1 ( ) MemberKind.GeneralizedFunctionType',
          'endFunctionType Function ',
        ]);
  }

  void test_computeType_void() {
    expectInfo(voidTypeInfo, 'void');
    expectInfo(voidTypeInfo, 'void;');
    expectInfo(voidTypeInfo, 'void(');
    expectInfo(voidTypeInfo, 'void<');
    expectInfo(voidTypeInfo, 'void=');
    expectInfo(voidTypeInfo, 'void*');
    expectInfo(voidTypeInfo, 'void<T>');
    expectInfo(voidTypeInfo, 'void do');
    expectInfo(voidTypeInfo, 'void foo');
    expectInfo(voidTypeInfo, 'void get');
    expectInfo(voidTypeInfo, 'void set');
    expectInfo(voidTypeInfo, 'void operator');
    expectInfo(voidTypeInfo, 'void Function');
    expectComplexInfo('void Function(', // Scanner inserts synthetic ')'.
        required: true,
        expectedCalls: [
          'handleNoTypeVariables (',
          'beginFunctionType void',
          'handleVoidKeyword void',
          'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
          'endFormalParameters 0 ( ) MemberKind.GeneralizedFunctionType',
          'endFunctionType Function ',
        ]);
  }

  void test_computeType_voidComplex() {
    expectInfo(voidTypeInfo, 'void Function()', required: false);
    expectComplexInfo('void Function()', required: true, expectedCalls: [
      'handleNoTypeVariables (',
      'beginFunctionType void',
      'handleVoidKeyword void',
      'beginFormalParameters ( MemberKind.GeneralizedFunctionType',
      'endFormalParameters 0 ( ) MemberKind.GeneralizedFunctionType',
      'endFunctionType Function ',
    ]);

    expectInfo(voidTypeInfo, 'void Function<T>()', required: false);
    expectInfo(voidTypeInfo, 'void Function(int)', required: false);
    expectInfo(voidTypeInfo, 'void Function<T>(int)', required: false);
    expectInfo(voidTypeInfo, 'void Function(int x)', required: false);
    expectInfo(voidTypeInfo, 'void Function<T>(int x)', required: false);

    expectComplexInfo('void Function<T>()', required: true);
    expectComplexInfo('void Function(int)', required: true);
    expectComplexInfo('void Function<T>(int)', required: true);
    expectComplexInfo('void Function(int x)', required: true);
    expectComplexInfo('void Function<T>(int x)', required: true);

    expectComplexInfo('void Function<T>(int x) Function<T>(int x)',
        required: false, tokenAfter: 'Function');
    expectComplexInfo('void Function<T>(int x) Function<T>(int x)',
        required: true);
  }
}

void expectInfo(expectedInfo, String source,
    {bool required,
    String expectedAfter,
    List<String> expectedCalls,
    List<ExpectedError> expectedErrors}) {
  Token start = scan(source);
  if (required == null) {
    compute(expectedInfo, source, start, true, expectedAfter, expectedCalls,
        expectedErrors);
    compute(expectedInfo, source, start, false, expectedAfter, expectedCalls,
        expectedErrors);
  } else {
    compute(expectedInfo, source, start, required, expectedAfter, expectedCalls,
        expectedErrors);
  }
}

void expectComplexInfo(String source,
    {bool required,
    String tokenAfter,
    List<String> expectedCalls,
    List<ExpectedError> expectedErrors}) {
  expectInfo(const isInstanceOf<ComplexTypeInfo>(), source,
      required: required,
      expectedAfter: tokenAfter,
      expectedCalls: expectedCalls,
      expectedErrors: expectedErrors);
}

void compute(
    expectedInfo,
    String source,
    Token start,
    bool required,
    String expectedAfter,
    List<String> expectedCalls,
    List<ExpectedError> expectedErrors) {
  TypeInfo typeInfo = computeType(start, required);
  expect(typeInfo, expectedInfo, reason: source);
  if (typeInfo is ComplexTypeInfo) {
    expect(typeInfo.start, start.next, reason: source);
    expect(typeInfo.couldBeExpression, isFalse);
    expectEnd(expectedAfter, typeInfo.skipType(start));

    TypeInfoListener listener;
    assertResult(Token actualEnd) {
      expectEnd(expectedAfter, actualEnd);
      if (expectedCalls != null) {
        // TypeInfoListener listener2 = new TypeInfoListener();
        // new Parser(listener2).parseType(start, TypeContinuation.Required);
        // print('[');
        // for (String call in listener2.calls) {
        //   print("'$call',");
        // }
        // print(']');

        expect(listener.calls, expectedCalls, reason: source);
      }
      expect(listener.errors, expectedErrors, reason: source);
    }

    listener = new TypeInfoListener();
    assertResult(typeInfo.parseType(start, new Parser(listener)));
  } else {
    assert(expectedErrors == null);
  }
}

void expectEnd(String tokenAfter, Token end) {
  if (tokenAfter == null) {
    expect(end.isEof, isFalse);
    expect(end.next.isEof, isTrue);
  } else {
    expect(end.next.lexeme, tokenAfter);
  }
}

Token scan(String source) {
  Token start = scanString(source).tokens;
  while (start is ErrorToken) {
    start = start.next;
  }
  return new SyntheticToken(TokenType.EOF, 0)..setNext(start);
}

class TypeInfoListener implements Listener {
  List<String> calls = <String>[];
  List<ExpectedError> errors;

  @override
  void beginFormalParameter(Token token, MemberKind kind) {
    calls.add('beginFormalParameter $token $kind');
  }

  @override
  void beginFormalParameters(Token token, MemberKind kind) {
    calls.add('beginFormalParameters $token $kind');
  }

  @override
  void beginFunctionType(Token token) {
    calls.add('beginFunctionType $token');
  }

  @override
  void beginMetadataStar(Token token) {
    calls.add('beginMetadataStar $token');
  }

  @override
  void beginTypeArguments(Token token) {
    calls.add('beginTypeArguments $token');
  }

  @override
  void beginTypeVariable(Token token) {
    calls.add('beginTypeVariable $token');
  }

  @override
  void endFormalParameters(
      int count, Token beginToken, Token endToken, MemberKind kind) {
    calls.add('endFormalParameters $count $beginToken $endToken $kind');
  }

  @override
  void beginTypeVariables(Token token) {
    calls.add('beginTypeVariables $token');
  }

  @override
  void endFormalParameter(Token thisKeyword, Token periodAfterThis,
      Token nameToken, FormalParameterKind kind, MemberKind memberKind) {
    calls.add('beginTypeVariables $thisKeyword $periodAfterThis '
        '$nameToken $kind $memberKind');
  }

  @override
  void endFunctionType(Token functionToken, Token endToken) {
    calls.add('endFunctionType $functionToken $endToken');
  }

  @override
  void endMetadataStar(int count) {
    calls.add('endMetadataStar $count');
  }

  @override
  void endTypeArguments(int count, Token beginToken, Token endToken) {
    calls.add('endTypeArguments $count $beginToken $endToken');
  }

  @override
  void endTypeVariable(Token token, Token extendsOrSuper) {
    calls.add('endTypeVariable $token $extendsOrSuper');
  }

  @override
  void endTypeVariables(int count, Token beginToken, Token endToken) {
    calls.add('endTypeVariables $count $beginToken $endToken');
  }

  @override
  void handleFormalParameterWithoutValue(Token token) {
    calls.add('handleFormalParameterWithoutValue $token');
  }

  @override
  void handleIdentifier(Token token, IdentifierContext context) {
    calls.add('handleIdentifier $token $context');
  }

  @override
  void handleModifiers(int count) {
    calls.add('handleModifiers $count');
  }

  @override
  void handleNoName(Token token) {
    calls.add('handleNoName $token');
  }

  @override
  void handleNoType(Token token) {
    calls.add('handleNoType $token');
  }

  @override
  void handleNoTypeArguments(Token token) {
    calls.add('handleNoTypeArguments $token');
  }

  @override
  void handleNoTypeVariables(Token token) {
    calls.add('handleNoTypeVariables $token');
  }

  @override
  void handleRecoverableError(
      Message message, Token startToken, Token endToken) {
    errors ??= <ExpectedError>[];
    int offset = startToken.charOffset;
    errors.add(error(message.code, offset, endToken.charEnd - offset));
  }

  @override
  void handleQualified(Token token) {
    calls.add('handleQualified $token');
  }

  @override
  void handleType(Token beginToken, Token endToken) {
    calls.add('handleType $beginToken $endToken');
  }

  @override
  void handleVoidKeyword(Token token) {
    calls.add('handleVoidKeyword $token');
  }

  noSuchMethod(Invocation invocation) {
    throw '${invocation.memberName} should not be called.';
  }
}

ExpectedError error(Code code, int start, int length) =>
    new ExpectedError(code, start, length);

class ExpectedError {
  final Code code;
  final int start;
  final int length;

  ExpectedError(this.code, this.start, this.length);

  @override
  bool operator ==(other) =>
      other is ExpectedError &&
      code == other.code &&
      start == other.start &&
      length == other.length;

  @override
  String toString() => 'error(${code.name}, $start, $length)';
}
