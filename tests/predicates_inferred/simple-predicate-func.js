// @flow

function is_string(y: mixed): %checks {
  return typeof y === "string";
}

function is_bool(y: mixed): %checks {
  return typeof y === "boolean";
}

function is_number(y: mixed): %checks {
  return typeof y === "number";
}

// Feature check:
function foo1(x: string | Array<string>): string {
  if (is_string(x)) {
    // The use of `is_string` as a conditional check
    // should guarantee the narrowing of the type of `x`
    // to string.
    return x;
  } else {
    // Accordingly the negation of the above check
    // guarantees that `x` here is an Array<string>
    return x.join();
  }
}

// Same as above but refining an offset
function bar(z: { f: string | Array<string>}): string {
  if (is_string(z.f)) {
    return z.f;
  } else {
    return z.f.join();
  }
}

function is_number_or_bool(y: mixed): %checks {
  return is_number(y) || is_bool(y);
}

function baz(z: string | number): number {
  if (is_number_or_bool(z)) {
    return z;
  } else {
    return z.length;
  }
}

// Feature: multi params
function multi_param(w:mixed,x:mixed,y:mixed,z:mixed): %checks {
  return typeof z === "string";
}

function foo2(x: string | Array<string>): string {
  if (multi_param("1", "2", "3", x)) {
    return x;
  } else {
    return x.join();
  }
}

function foo3(a: mixed, b: mixed) {
  if (two_strings(a, b)) {
    from_two_strings(a, b);
  }
}

function two_strings(x: mixed,y: mixed): %checks {
  return is_string(x) && is_string(y) ;
}

declare function from_two_strings(x: string, y: string): void;

const two_strings_arrow = (x: mixed,y: mixed): %checks =>
  is_string(x) && is_string(y);
