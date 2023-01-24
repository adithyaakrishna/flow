//@flow

var call_me: () => void = () => {};

function g(x: ?number) {
  var var_x = x;
  if (var_x) {
    // error: var_x might no longer be truthy when call_me is called
    call_me = () => {
      var y:number = var_x;
    };  // error
  }
  var_x = null;
}

function havoc_uninitialized() {
  var x: void | number;

  function havoc() {
    x = undefined;
  }
  havoc();
  (x: void); // should error
}

function havoc_annotated() {
  var x: number | string = 42;
  function havoc() {
    x = "hello"
  }
  if (typeof x === 'number') {
    havoc();
    (x: number); // should fail
  }
}

function test_unsealed() {
  // unsealed objects are unsound
  let x = {}

  function f(g: {|b: string|}) {
    return {...g, ...x}; // no error here, unsoundly.
  }

  function g() {
    x = ({a: 42}: {a: number, ...}); // no error here
  }
}

function param(
  cf: ?number,
) {
    cf = cf; // no error, ofc
  }

function branch_error() {
  const f1 = ((y: empty) => 42); // error, x has number as LB
  const f2 = ((y: empty) => 42); // error, x has number as LB

  declare var f: (typeof f1) & (typeof f2);

  function fn() {
    let fn = (x: number) => 42;
    function havoc() {
      fn = f;
    }
    fn(52);
  }
}
