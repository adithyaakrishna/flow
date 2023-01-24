---
title: Utility Types
slug: /types/utilities
---

Flow provides a set of utility types to operate on other types, and can be useful for different scenarios.

## `$Keys<T>` {#toc-keys}

In Flow you can [use union types similar to enums](../literals/):

```js flow-check
// @flow
type Suit = "Diamonds" | "Clubs" | "Hearts" | "Spades";

const clubs: Suit = 'Clubs';
const wrong: Suit = 'wrong'; // 'wrong' is not a Suit
```

This is very handy, but sometimes you need to access the enum definition at runtime (i.e. at a value level).

Suppose for example that you want to associate a value to each suit of the previous example.

You could do

```js flow-check
// @flow
type Suit = "Diamonds" | "Clubs" | "Hearts" | "Spades";

const suitNumbers = {
  Diamonds: 1,
  Clubs: 2,
  Hearts: 3,
  Spades: 4
};

function printSuitNumber(suit: Suit) {
  console.log(suitNumbers[suit]);
}

printSuitNumber('Diamonds'); // 1
printSuitNumber('foo'); // 'foo' is not a Suit
```

but this doesn't feel very DRY, as we had to explicitly define the suit names twice.

In situations like this one, you can leverage the `$Keys<T>` operator. Let's see another example, this time using `$Keys`:

```js flow-check
// @flow
const countries = {
  US: "United States",
  IT: "Italy",
  FR: "France"
};

type Country = $Keys<typeof countries>;

const italy: Country = 'IT';
const nope: Country = 'nope'; // 'nope' is not a Country
```

In the example above, the type of `Country` is equivalent to `type Country = 'US' | 'IT' | 'FR'`, but Flow was able to extract it from the keys of `countries`.

## `$Values<T>` {#toc-values}

`$Values<T>` represents the union type of all the value types (not the values, but their *types*!) of the enumerable properties in an [Object Type](../objects/) `T`.

For example:
```js flow-check
// @flow
type Props = {
  name: string,
  age: number,
};

// The following two types are equivalent:
type PropValues = string | number;
type Prop$Values = $Values<Props>;

const name: Prop$Values = 'Jon';  // OK
const age: Prop$Values = 42;  // OK
const fn: Prop$Values = () => {};  // Error! function is not part of the union type
```

## `$ReadOnly<T>` {#toc-readonly}

`$ReadOnly<T>` is a type that represents the read-only version of a given [object type](../objects/) `T`. A read-only object type is an object type whose keys are all [read-only](../interfaces/#toc-interface-property-variance-read-only-and-write-only).

This means that the following 2 types are equivalent:
```js flow-check
type ReadOnlyObj = {
  +key: any,  // read-only field, marked by the `+` annotation
};
```
```js flow-check
type ReadOnlyObj = $ReadOnly<{
  key: any,
}>;
```

This is useful when you need to use a read-only version of an object type you've already defined, without manually having to re-define and annotate each key as read-only. For example:

```js flow-check
// @flow
type Props = {
  name: string,
  age: number,
  // ...
};

type ReadOnlyProps = $ReadOnly<Props>;

function render(props: ReadOnlyProps) {
  const {name, age} = props;  // OK to read
  props.age = 42;             // Error when writing
  // ...
}
```

Additionally, other utility types, such as [`$ObjMap<T>`](#toc-objmap), may strip any read/write annotations, so `$ReadOnly<T>` is a handy way to quickly make the object read-only again after operating on it:

```js flow-check
type Obj = {
  +key: any,
};

type MappedObj = $ReadOnly<$ObjMap<Obj, TypeFn>> // Still read-only
```

> Note: `$ReadOnly` is only for making read-only _object_ types. See the Array docs
> for how to [type read-only arrays with `$ReadOnlyArray`](../arrays/#toc-readonlyarray).

## `$Exact<T>` {#toc-exact}

`$Exact<{name: string}>` is a synonym for `{| name: string |}` as in the [Object documentation](../objects/#toc-exact-object-types).

```js flow-check
// @flow
type ExactUser = $Exact<{name: string}>;
type ExactUserShorthand = {| name: string |};

const user2 = {name: 'John Wilkes Booth'};
// These will both be satisfied because they are equivalent
(user2: ExactUser);
(user2: ExactUserShorthand);
```

## `$Diff<A, B>` {#toc-diff}

As the name hints, `$Diff<A, B>` is the type representing the set difference of `A` and `B`, i.e. `A \ B`, where `A` and `B` are both [object types](../objects/). Here's an example:

```js flow-check
// @flow
type Props = { name: string, age: number };
type DefaultProps = { age: number };
type RequiredProps = $Diff<Props, DefaultProps>;

function setProps(props: RequiredProps) {
  // ...
}

setProps({ name: 'foo' });
setProps({ name: 'foo', age: 42, baz: false }); // you can pass extra props too
setProps({ age: 42 }); // error, name is required
```

As you may have noticed, the example is not a random one. `$Diff` is exactly what the React definition file uses to define the type of the props accepted by a React Component.

Note that `$Diff<A, B>` will error if the object you are removing properties from does not have the property being removed, i.e. if `B` has a key that doesn't exist in `A`:

```js flow-check
// @flow
type Props = { name: string, age: number };
type DefaultProps = { age: number, other: string }; // Will error due to this `other` property not being in Props.
type RequiredProps = $Diff<Props, DefaultProps>;

function setProps(props: RequiredProps) {
  props.name;
  // ...
}
```

As a workaround, you can specify the property not present in `A` as optional. For example:

```js flow-check
type A = $Diff<{}, {nope: number}>; // Error
type B = $Diff<{}, {nope: number | void}>; // OK
```

## `$Rest<A, B>` {#toc-rest}

`$Rest<A, B>` is the type that represents the runtime object rest operation, e.g.: `const {foo, ...rest} = obj`, where `A` and `B` are both [object types](../objects/). The resulting type from this operation will be an object type containing `A`'s *own* properties that are not *own* properties in `B`. In flow, we treat all properties on [exact object types](../objects/#toc-exact-object-types) as [own](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/hasOwnProperty). In in-exact objects, a property may or may not be own.

For example:

```js flow-check
// @flow
type Props = { name: string, age: number };

const props: Props = {name: 'Jon', age: 42};
const {age, ...otherProps} = props;
(otherProps: $Rest<Props, {|age: number|}>);
otherProps.age;  // Error
```

The main difference with [`$Diff<A, B>`](#toc-diff), is that `$Rest<A, B>` aims to represent the true runtime rest operation, which implies that exact object types are treated differently in `$Rest<A, B>`. For example, `$Rest<{|n: number|}, {}>` will result in `{|n?: number|}` because an in-exact empty object may have an `n` property, while `$Diff<{|n: number|}, {}>` will result in `{|n: number|}`.

## `$PropertyType<T, k>` {#toc-propertytype}

**WARNING:** `$PropertyType` is deprecated as of Flow version 0.155, and will be removed in a future version of Flow. Use [Indexed Access Types](../indexed-access) instead. `$PropertyType<T, 'k'>` is now `T['k']`.

A `$PropertyType<T, k>` is the type at a given key `k`. As of Flow v0.36.0, `k` must be a literal string.

```js flow-check
// @flow
type Person = {
  name: string,
  age: number,
  parent: Person
};

const newName: $PropertyType<Person, 'name'> = 'Toni Braxton';
const newAge: $PropertyType<Person, 'age'> = 51;
const newParent: $PropertyType<Person, 'parent'> = 'Evelyn Braxton';
```

This can be especially useful for referring to the type of React props, or, even the entire `props` type itself.

```js flow-check
// @flow
import React from 'react';

type Props = {
  text: string,
  onMouseOver: ({x: number, y: number}) => void
}

class Tooltip extends React.Component<Props> {
  props: Props;
}

const someProps: $PropertyType<Tooltip, 'props'> = {
  text: 'foo',
  onMouseOver: (data: {x: number, y: number}) => undefined
};

const otherProps: $PropertyType<Tooltip, 'props'> = {
  text: 'foo'
  // Missing the `onMouseOver` definition
};
```

You can even nest lookups:

```js flow-check
// @flow
type PositionHandler = $PropertyType<$PropertyType<Tooltip, 'props'>, 'onMouseOver'>;
const handler: PositionHandler = (data: {x: number, y: number}) => undefined;
const handler2: PositionHandler = (data: string) => undefined; // wrong parameter types
```

You can use this in combination with `Class<T>` to get static props:

```js flow-check
// @flow
class BackboneModel {
  static idAttribute: string | false;
}

type ID = $PropertyType<Class<BackboneModel>, 'idAttribute'>;
const someID: ID = '1234';
const someBadID: ID = true;
```

## `$ElementType<T, K>` {#toc-elementtype}

**WARNING:** `$ElementType` is deprecated as of Flow version 0.155, and will be removed in a future version of Flow. Use [Indexed Access Types](../indexed-access) instead. `$ElementType<T, K>` is now `T[K]`.

`$ElementType<T, K>` is the type that represents the type of every element inside an [array](../arrays), [tuple](../tuples) or [object](../objects) type `T`, that matches the given *key* type `K`.

For example:
```js flow-check
// @flow

// Using objects:
type Obj = {
  name: string,
  age: number,
}
('Jon': $ElementType<Obj, 'name'>);
(42: $ElementType<Obj, 'age'>);
(true: $ElementType<Obj, 'name'>); // Nope, `name` is not a boolean
(true: $ElementType<Obj, 'other'>); // Nope, property `other` is not in Obj

// Using tuples:
type Tuple = [boolean, string];
(true: $ElementType<Tuple, 0>);
('foo': $ElementType<Tuple, 1>);
('bar': $ElementType<Tuple, 2>); // Nope, can't access position 2
```

In the above case, we're using literal values as `K`, similarly to [`$PropertyType<T, k>`](#toc-propertytype). However, when using `$ElementType<T, K>`, `K` is allowed to be any type, as long as that type exists on the keys of `T`. For example:

```js flow-check
// @flow

// Using objects
type Obj = { [key: string]: number };
(42: $ElementType<Obj, string>);
(42: $ElementType<Obj, boolean>); // Nope, object keys aren't booleans
(true: $ElementType<Obj, string>); // Nope, elements are numbers


// Using arrays, we don't statically know the size of the array, so you can just use the `number` type as the key:
type Arr = Array<boolean>;
(true: $ElementType<Arr, number>);
(true: $ElementType<Arr, boolean>); // Nope, array indices aren't booleans
('foo': $ElementType<Arr, number>); // Nope, elements are booleans
```

You can also nest calls to `$ElementType<T, K>`, which is useful when you need to access the types inside nested structures:

```js flow-check
// @flow
type NumberObj = {
  nums: Array<number>,
};

(42: $ElementType<$ElementType<NumberObj, 'nums'>, number>);
```

Additionally, one of the things that also makes `$ElementType<T, K>` more powerful than [`$PropertyType<T, k>`](#toc-propertytype) is that you can use it with generics. For example:

```js flow-check
// @flow
function getProp<O: {+[string]: mixed}, P: $Keys<O>>(o: O, p: P): $ElementType<O, P> {
  return o[p];
}

(getProp({a: 42}, 'a'): number); // OK
(getProp({a: 42}, 'a'): string); // Error: number is not a string
getProp({a: 42}, 'b'); // Error: `b` does not exist
```

## `$NonMaybeType<T>` {#toc-nonmaybe}

`$NonMaybeType<T>` converts a type `T` to a non-maybe type. In other words, the values of `$NonMaybeType<T>` are the values of `T` except for `null` and `undefined`.

```js flow-check
// @flow
type MaybeName = ?string;
type Name = $NonMaybeType<MaybeName>;

('Gabriel': MaybeName); // Ok
(null: MaybeName); // Ok
('Gabriel': Name); // Ok
(null: Name); // Error! null can't be annotated as Name because Name is not a maybe type
```

## `$ObjMap<T, F>` {#toc-objmap}

`ObjMap<T, F>` takes an [object type](../objects) `T`, and a [function type](../functions) `F`, and returns the object type obtained by mapping the type of each value in the object with the provided function type `F`. In other words, `$ObjMap` will [call](#toc-call) (at the type level) the given function type `F` for every property value type in `T`, and return the resulting object type from those calls.

Let's see an example. Suppose you have a function called `run` that takes an object of thunks (functions in the form `() => A`) as input:

```js flow-check
// @flow
function run<O: {[key: string]: Function}>(o: O) {
  return Object.keys(o).reduce((acc, k) => Object.assign(acc, { [k]: o[k]() }), {});
}
```

The function's purpose is to run all the thunks and return an object made of values. What's the return type of this function?

The keys are the same, but the values have a different type, namely the return type of each function. At a value level (the implementation of the function) we're essentially mapping over the object to produce new values for the keys. How to express this at a type level?

This is where `ObjMap<T, F>` comes in handy.

```js flow-check
// @flow

// let's write a function type that takes a `() => V` and returns a `V` (its return type)
type ExtractReturnType = <V>(() => V) => V;

declare function run<O: {[key: string]: Function}>(o: O): $ObjMap<O, ExtractReturnType>;

const o = {
  a: () => true,
  b: () => 'foo'
};

(run(o).a: boolean); // Ok
(run(o).b: string);  // Ok
// $ExpectError
(run(o).b: boolean); // Nope, b is a string
// $ExpectError
run(o).c;            // Nope, c was not in the original object
```

This is extremely useful for expressing the return type of functions that manipulate objects values. You could use a similar approach (for instance) to provide the return type of bluebird's [`Promise.props`](http://bluebirdjs.com/docs/api/promise.props.html) function, which is like `Promise.all` but takes an object as input.

Here's a possible declaration of this function, which is very similar to our first example:

```js flow-check
// @flow
declare function props<A, O: { [key: string]: A }>(promises: O): Promise<$ObjMap<O, typeof $await>>;
```

And use:

```js flow-check
// @flow
const promises = { a: Promise.resolve(42) };
props(promises).then(o => {
  (o.a: 42); // Ok
  // $ExpectError
  (o.a: 43); // Error, flow knows it's 42
});
```

## `$ObjMapi<T, F>` {#toc-objmapi}

`ObjMapi<T, F>` is similar to [`ObjMap<T, F>`](#toc-objmap). The difference is that function
type `F` will be [called](#toc-call) with both the key and value types of the elements of
the object type `T`, instead of just the value types. For example:

```js flow-check
// @flow
const o = {
  a: () => true,
  b: () => 'foo'
};

type ExtractReturnObjectType = <K, V>(K, () => V) => { k: K, v: V };

declare function run<O: {...}>(o: O): $ObjMapi<O, ExtractReturnObjectType>;

(run(o).a: { k: 'a', v: boolean }); // Ok
(run(o).b: { k: 'b', v: string });  // Ok
// $ExpectError
(run(o).a: { k: 'b', v: boolean }); // Nope, a.k is "a"
// $ExpectError
(run(o).b: { k: 'b', v: number });  // Nope, b.v is a string
// $ExpectError
run(o).c;                           // Nope, c was not in the original object
```

## `$ObjMapConst<O, T>` {#toc-objmapconst}

`$ObjMapConst<Obj, T>` is a special case of `$ObjMap<Obj, F>`, when `F` is a constant
function type, e.g. `() => T`. Instead of writing `$ObjMap<Obj, () => T>`, you
can write `$ObjMapConst<Obj, T>`. For example:
```js
// @flow
const obj = {
  a: true,
  b: 'foo'
};

declare function run<O: {...}>(o: O): $ObjMapConst<O, number>;

// newObj is of type {a: number, b: number}
const newObj = run(obj);

(newObj.a: number); // Ok
// $ExpectedError
(newObj.b: string); // Error property b is a number
```

Tip: Prefer using `$ObjMapConst` instead of `$ObjMap` (if possible) to fix certain
kinds of `[invalid-exported-annotation]` errors.

## `$KeyMirror<O>` {#toc-keymirror}

`$KeyMirror<Obj>` is a special case of `$ObjMapi<Obj, F>`, when `F` is the identity
function type, ie. `<K>(K) => K`. In other words, it maps each property of an object
to the type of the property key. Instead of writing `$ObjMapi<Obj, <K>(K) => K>`,
you can write `$KeyMirror<Obj>`. For example:
```js
// @flow
const obj = {
  a: true,
  b: 'foo'
};

declare function run<O: {...}>(o: O): $KeyMirror<O>;

// newObj is of type {a: 'a', b: 'b'}
const newObj = run(obj);

(newObj.a: 'a'); // Ok
// $ExpectedError
(newObj.b: 'a'); // Error string 'b' is incompatible with 'a'
```

Tip: Prefer using `$KeyMirror` instead of `$ObjMapi` (if possible) to fix certain
kinds of `[invalid-exported-annotation]` errors.

## `$TupleMap<T, F>` {#toc-tuplemap}

`$TupleMap<T, F>` takes an iterable type `T` (e.g.: [`Tuple`](../tuples) or [`Array`](../arrays)), and a [function type](../functions) `F`, and returns the iterable type obtained by mapping the type of each value in the iterable with the provided function type `F`. This is analogous to the Javascript function `map`.

Following our example from [`$ObjMap<T>`](#toc-objmap), let's assume that `run` takes an array of functions, instead of an object, and maps over them returning an array of the function call results. We could annotate its return type like this:

```js flow-check
// @flow

// Function type that takes a `() => V` and returns a `V` (its return type)
type ExtractReturnType = <V>(() => V) => V

function run<A, I: Array<() => A>>(iter: I): $TupleMap<I, ExtractReturnType> {
  return iter.map(fn => fn());
}

const arr = [() => 'foo', () => 'bar'];
(run(arr)[0]: string); // OK
(run(arr)[1]: string); // OK
(run(arr)[1]: boolean); // Error
```

## `$Call<F, T...>` {#toc-call}

`$Call<F, T...>` is a type that represents the result of calling the given [function type](../functions) `F` with 0 or more arguments `T...`. This is analogous to calling a function at runtime (or more specifically, it's analogous to calling [`Function.prototype.call`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Function/call)), but at the type level; this means that function type calls happens statically, i.e. not at runtime.

Let's see a couple of examples:
```js flow-check
// @flow

// Takes an object type, returns the type of its `prop` key
type ExtractPropType = <T>({prop: T}) => T;
type Obj = {prop: number};
type PropType = $Call<ExtractPropType, Obj>;  // Call `ExtractPropType` with `Obj` as an argument
type Nope = $Call<ExtractPropType, {nope: number}>;  // Error: argument doesn't match `Obj`.

(5: PropType); // OK
(true: PropType);  // Error: PropType is a number
(5: Nope);  // Error
```

```js flow-check
// @flow

// Takes a function type, and returns its return type
// This is useful if you want to get the return type of some function without actually calling it at runtime.
type ExtractReturnType = <R>(() => R) => R;
type Fn = () => number;
type ReturnType = $Call<ExtractReturnType, Fn> // Call `ExtractReturnType` with `Fn` as an argument

(5: ReturnType);  // OK
(true: ReturnType);  // Error: ReturnType is a number
```

`$Call` can be very powerful because it allows you to make calls in type-land that you would otherwise have to do at runtime. The type-land calls happen statically and will be erased at runtime.

Let's look at a couple of more advanced examples:

```js flow-check
// @flow

// Extracting deeply nested types:
type NestedObj = {|
  +status: ?number,
  +data: ?$ReadOnlyArray<{|
    +foo: ?{|
       +bar: number,
    |},
  |}>,
|};

// If you wanted to extract the type for `bar`, you could use $Call:
type BarType = $Call<
  <T>({
    +data: ?$ReadOnlyArray<{
      +foo: ?{
        +bar: ?T
      },
    }>,
  }) => T,
  NestedObj,
>;

(5: BarType);
(true: BarType);  // Error: `bar` is not a boolean
```

```js flow-check
// @flow

// Getting return types:
function getFirstValue<V>(map: Map<string, V>): ?V {
  for (const [key, value] of map.entries()) {
    return value;
  }
  return null;
}

// Using $Call, we can get the actual return type of the function above, without calling it at runtime:
type Value = $Call<typeof getFirstValue, Map<string, number>>;

(5: Value);
(true: Value);  // Error: Value is a `number`


// We could generalize it further:
type GetMapValue<M> =
  $Call<typeof getFirstValue, M>;

(5: GetMapValue<Map<string, number>>);
(true: GetMapValue<Map<string, boolean>>);
(true: GetMapValue<Map<string, number>>);  // Error: value is a `number`
```

## `Class<T>` {#toc-class}

Given a type `T` representing instances of a class `C`, the type `Class<T>` is the type of the class `C`.
For example:

```js flow-check
// @flow
class Store {}
class ExtendedStore extends Store {}
class Model {}

function makeStore(storeClass: Class<Store>) {
  return new storeClass();
}

(makeStore(Store): Store);
(makeStore(ExtendedStore): Store);
(makeStore(Model): Model); // error
(makeStore(ExtendedStore): Model); // Flow infers the return type
```

For classes that take type parameters, you must also provide the parameter. For example:

```js flow-check
// @flow
class ParamStore<T> {
  constructor(data: T) {}
}

function makeParamStore<T>(storeClass: Class<ParamStore<T>>, data: T): ParamStore<T> {
  return new storeClass(data);
}
(makeParamStore(ParamStore, 1): ParamStore<number>);
(makeParamStore(ParamStore, 1): ParamStore<boolean>); // failed because of the second parameter
```

## `$Partial<T>` {#toc-partial}
This utility converts all of an object or interface's named fields to be optional, while maintaining all the object's other properties (e.g. exactness). Use this utility instead of `$Shape`.

```js flow-check
type Person = {
  age: number,
  name: string,
};
type PersonDetails = $Partial<Person>;

const person1: Person = {age: 28};  // Error: missing `name`
const person2: Person = {name: 'a'};  // Error: missing `age`

const personDetails1: PersonDetails = {age: 28};  // OK
const personDetails2: PersonDetails = {name: 'a'};  // OK
const personDetails3: PersonDetails = {age: 28, name: 'a'};  // OK
const personDetails4: PersonDetails = {age: 'a'};  // Error: string is incompatible with number

(personDetails1: Person); // Error: `PersonDetails` is not a `Person` (unlike with `$Shape`)
```

## `$Shape<T>` {#toc-shape}

> NOTE: This utility is unsafe - please use [`$Partial`](#toc-partial) documented above to make all of an object's fields optional.

A variable of type `$Shape<T>`, where `T` is some object type, can be assigned objects `o`
that contain a subset of the properties included in `T`. For each property `p: S` of `T`,
the type of a potential binding of `p` in `o` must be compatible with `S`.

For example
```js flow-check
// @flow
type Person = {
  age: number,
  name: string,
}
type PersonDetails = $Shape<Person>;

const person1: Person = {age: 28};  // Error: missing `name`
const person2: Person = {name: 'a'};  // Error: missing `age`
const person3: PersonDetails = {age: 28};  // OK
const person4: PersonDetails = {name: 'a'};  // OK
const person5: PersonDetails = {age: 28, name: 'a'};  // OK
const person6: PersonDetails = {age: '28'};  // Error: string is incompatible with number
```

> Note: `$Shape<T>` is **not** equivalent to `T` with all its fields marked as optional.
> In particular, Flow unsoundly allows `$Shape<T>` to be used as a `T` in several
> contexts. For example in
```
const personShape: PersonDetails = {age: 28};
(personShape: Person);
```
Flow will unsoundly allow this last cast to succeed. If this behavior is not wanted,
then this utility type should be avoided - use [`$Partial`](#toc-partial) instead.

## `$Exports<T>` {#toc-exports}

The following are functionally equivalent

```js
import typeof * as T from 'my-module';
```

```js
type T = $Exports<'my-module'>;
```

The advantage of the `$Exports` syntax is that you can `export` the type on the same line
```js
export type T = $Exports<'my-module'>;
```

where as you would otherwise need to export an alias in the `import typeof` case
```js
import typeof * as T from 'my-module';
export type MyModuleType = T;
```

## Existential Type (`*`) {#toc-existential-type}

This utility has been deprecated and should be avoided. See [here](../../linting/rule-reference#toc-deprecated-type) for details.
