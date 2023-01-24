//@flow
declare function f<T>(): T;
f(); // Error: T underconstrained

declare function g<T>(T => mixed): T;
g((x: number) => 'string'); // Ok: It will error under Pierce, but we also consider upper bounds here.

declare function h<T>(T): T => mixed;
h(3); // Ok: It will error under Pierce, but we also consider lower bounds here.

declare function i<T>(): Array<T>;
i(); // Error: T underconstrained
