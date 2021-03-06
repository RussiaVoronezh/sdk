// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/expect.dart";

// Tests that const/new-insertion does the right thing for
// composite object creations.
//
// The right thing is that map and list literals are only constant
// if in a constant context.
// Object creation is const if constructor is const and all arguments are const.
//
// Not testing inference, so all type arguments are explicit.

main() {
  var x = 42;
  const cc42 = const C(42);
  var c42 = cc42;

  const clist = const <int>[37];
  var list = clist;
  const cmap = const <int, int>{19: 87};
  var map = cmap;

  {
    // Constructor inside constructor.
    var d42 = const D<int>(42);

    const cd1 = const C(const D<int>(42));
    const cd2 = C(D<int>(42)); // Const context.
    var cd3 = C(D<int>(42)); // Non-constant context, so `new`.
    var cd4 = C(D<int>(x)); // Non-constant context, so `new`.
    var cd5 = C(d42); // Non-constant context, so `new`.

    Expect.identical(cd1, cd2);
    Expect.allDistinct([cd1, cd3]);
    Expect.allDistinct([cd1, cd4, cd5]);
  }

  {
    // List inside other constructor
    const cl1 = const C(const <int>[37]);
    const cl2 = C(clist); // Constant context.
    const cl3 = C(const <int>[37]); // Constant context.
    const cl4 = C(<int>[37]);
    var cl5 = C(clist); // Non-constant context, so `new`.
    var cl6 = C(const <int>[37]); // Non-constant context, so `new`.
    var cl7 = C(list); // Non-constant context, so `new`.
    var cl8 = C(<int>[37]); // Non-constant context, so `new`.

    Expect.identical(cl1, cl2);
    Expect.identical(cl1, cl3);
    Expect.identical(cl1, cl4);
    Expect.allDistinct([cl1, cl5]);
    Expect.allDistinct([cl1, cl6]);
    Expect.allDistinct([cl1, cl7, cl8]);
  }

  {
    // Map inside other constructor.
    const cm1 = C(cmap); // Constant context.
    const cm2 = C(const <int, int>{19: 87}); // Constant context.
    const cm3 = C(<int, int>{19: 87}); // Constant context.
    var cm4 = C(cmap); // Non-constant context, so `new`.
    var cm5 = C(const <int, int>{19: 87}); // Non-constant context, so `new`.
    var cm6 = C(map); // Non-constant context, so `new`.
    var cm7 = C(<int, int>{19: 87}); // Non-constant context, so `new`.

    Expect.identical(cm1, cm2);
    Expect.identical(cm1, cm3);
    Expect.allDistinct([cm1, cm4]);
    Expect.allDistinct([cm1, cm5]);
    Expect.allDistinct([cm1, cm6, cm7]);
  }

  {
    // Composite with more than one sub-expression.
    const n1 = N(clist, cmap);
    const n2 = N(const <int>[37], const <int, int>{19: 87});
    const n3 = N(<int>[37], <int, int>{19: 87});
    var n4 = N(const <int>[37], const <int, int>{19: 87});
    var n5 = N(<int>[37], const <int, int>{19: 87});
    var n6 = N(const <int>[37], <int, int>{19: 87});
    var n7 = N(<int>[37], <int, int>{19: 87});
    var n8 = N(clist, cmap);
    var n9 = N(<int>[37], cmap);
    var n10 = N(clist, <int, int>{19: 87});
    var n11 = N(<int>[37], <int, int>{19: 87});
    var n12 = N(list, cmap);
    var n13 = N(clist, map);
    var n14 = N(list, map);

    Expect.identical(n1, n2);
    Expect.identical(n1, n3);
    Expect.allDistinct([n1, n4]);
    Expect.allDistinct([n1, n8]);
    Expect.allDistinct([n1, n5, n6, n7, n9, n10, n11, n12, n13, n14]);

    Expect.identical(clist, n6.left);
    Expect.identical(clist, n10.left);
    Expect.identical(clist, n12.left);
    Expect.identical(clist, n13.left);
    Expect.identical(clist, n14.left);
    Expect.allDistinct([n5.left, n7.left, n9.left, n11.left]);

    Expect.identical(cmap, n5.right);
    Expect.identical(cmap, n9.right);
    Expect.identical(cmap, n12.right);
    Expect.identical(cmap, n13.right);
    Expect.identical(cmap, n14.right);
    Expect.allDistinct([n6.right, n7.right, n10.right, n11.right]);

    const n20 = const N(const C(42), const <int>[37]);
    const n21 = N(const C(42), const <int>[37]);
    const n22 = N(C(42), const <int>[37]);
    const n23 = N(C(42), clist);
    const n24 = N(C(42), <int>[37]);
    var n25 = N(const C(42), const <int>[37]);
    var n26 = N(C(42), const <int>[37]);
    var n27 = N(C(42), clist);
    var n28 = N(C(42), <int>[37]);
    var n29 = N(C(42), list);
    var n30 = N(c42, clist);
    var n31 = N(cc42, list);

    Expect.identical(n20, n21);
    Expect.identical(n20, n22);
    Expect.identical(n20, n23);
    Expect.identical(n20, n24);
    Expect.allDistinct([n20, n25]);
    Expect.allDistinct([n20, n26]);
    Expect.allDistinct([n20, n27]);
    Expect.allDistinct([n28, n29, n30, n31]);
    Expect.allDistinct([cc42, n28.left]);
    Expect.allDistinct([cc42, n29.left]);
    Expect.identical(cc42, n30.left);
    Expect.identical(cc42, n31.left);
    Expect.identical(clist, n29.right);
    Expect.identical(clist, n30.right);
    Expect.identical(clist, n31.right);
    Expect.notIdentical(clist, n28.right);
  }

  {
    // List literals.
    const l20 = const [
      const C(42),
      const <int>[37]
    ];
    const l21 = [
      const C(42),
      const <int>[37]
    ];
    const l22 = [
      C(42),
      const <int>[37]
    ];
    var l23 = const [C(42), clist];
    const l24 = [
      C(42),
      <int>[37]
    ];
    var l25 = [
      const C(42),
      const <int>[37]
    ];
    var l26 = [
      C(42),
      const <int>[37]
    ];
    var l27 = [C(42), clist];
    var l28 = [
      C(42),
      <int>[37]
    ];
    var l29 = [C(42), list];
    var l30 = [c42, clist];
    var l31 = [cc42, list];

    Expect.identical(l20, l21);
    Expect.identical(l20, l22);
    Expect.identical(l20, l23);
    Expect.identical(l20, l24);
    // List literals are never const unless in const context.
    Expect.allDistinct([l20, l25, l26, l27, l28, l29, l30, l31]);
    Expect.identical(cc42, l25[0]);
    Expect.allDistinct([cc42, l26[0]]);
    Expect.allDistinct([cc42, l27[0]]);
    Expect.allDistinct([cc42, l28[0]]);
    Expect.allDistinct([cc42, l29[0]]);
    Expect.identical(cc42, l30[0]);
    Expect.identical(cc42, l31[0]);
    Expect.identical(clist, l25[1]);
    Expect.identical(clist, l26[1]);
    Expect.identical(clist, l27[1]);
    Expect.identical(clist, l29[1]);
    Expect.identical(clist, l30[1]);
    Expect.identical(clist, l31[1]);
    Expect.notIdentical(clist, l28[1]);
  }

  {
    // Map literals.
    const m20 = const <C, List<int>>{
      const C(42): const <int>[37]
    };
    const m21 = {
      const C(42): const <int>[37]
    };
    const m22 = {
      C(42): const <int>[37]
    };
    var m23 = const {C(42): clist};
    const m24 = {
      C(42): <int>[37]
    };
    var m25 = {
      const C(42): const <int>[37]
    };
    var m26 = {
      C(42): const <int>[37]
    };
    var m27 = {C(42): clist};
    var m28 = {
      C(42): <int>[37]
    };
    var m29 = {C(42): list};
    var m30 = {c42: clist};
    var m31 = {cc42: list};

    Expect.identical(m20, m21);
    Expect.identical(m20, m22);
    Expect.identical(m20, m23);
    Expect.identical(m20, m24);
    // Map literals are never const unless in const context.
    Expect.allDistinct([m20, m25, m26, m27, m28, m29, m30, m31]);
    Expect.identical(cc42, m25.keys.first);
    Expect.allDistinct([cc42, m26.keys.first]);
    Expect.allDistinct([cc42, m27.keys.first]);
    Expect.allDistinct([cc42, m28.keys.first]);
    Expect.allDistinct([cc42, m29.keys.first]);
    Expect.identical(cc42, m30.keys.first);
    Expect.identical(cc42, m31.keys.first);
    Expect.identical(clist, m25.values.first);
    Expect.identical(clist, m26.values.first);
    Expect.identical(clist, m27.values.first);
    Expect.identical(clist, m29.values.first);
    Expect.identical(clist, m30.values.first);
    Expect.identical(clist, m31.values.first);
    Expect.notIdentical(clist, m28.values.first);
  }
}

class C {
  final Object x;
  const C(this.x);
}

class D<T> {
  final T x;
  const D(this.x);
}

class N {
  final Object left, right;
  const N(this.left, this.right);
}
