// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Programmatically trigger breakpoints.
library dart.debugger;

/// Programmatically trigger breakpoints.
class Debugger {
  /// Stop the program as if a breakpoint where hit at the following statement.
  /// NOTE: When invoked, the isolate will not return until a debugger
  /// continues execution. When running in the Dart VM the behaviour is the same
  /// regardless of whether or not a debugger is connected. When compiled to
  /// JavaScript, this uses the "debugger" statement, and behaves exactly as
  /// that does.
  external static void breakHere();

  /// If [expr] is true, stop the program as if a breakpoint where hit at the
  /// following statement. See [breakHere].
  external static void breakHereIf(bool expr);
}
