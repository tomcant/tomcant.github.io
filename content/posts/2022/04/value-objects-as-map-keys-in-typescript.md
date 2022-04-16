---
title: "Value Objects as Map Keys in TypeScript"
date: 2022-04-16
draft: false
---

In [a previous post](/posts/2021/09/introduction-to-pathfinding-with-mazes-and-breadth-first-search/) I wrote about how
JavaScript's lack of support for value objects caused a problem when using the built-in `Set` class, and how it could be
solved by using the idea of a [Compound Set](https://eddmann.com/posts/implementing-a-compound-set-in-typescript/)
instead. In this post I'm going to describe a similar solution I've been using for the built-in `Map` class.

<!--more-->

## What's the Problem?

At the time of writing, JavaScript doesn't support immutability out of the box. Without it, we're unable to assert the
equality of objects from their value alone (using native features, at least).

Consider the following example in TypeScript:

```ts
type Point = {
  x: number;
  y: number;
};

const points = new Map<Point, string>();

points.set({ x: 0, y: 0 }, "The origin");
```

So far, so good, but unfortunately the following line produces an unexpected result:

```ts
points.get({ x: 0, y: 0 }); // undefined
```

This happens because JavaScript compares objects by reference, not by value, and the object passed to `set()` has a
different reference in memory to the object passed to `get()`.

Ideally, the `Point` type would describe a value object whose identity is defined by the values of its properties, but
JavaScript doesn't provide this kind of equality for objects.

## Third Party Libraries

There are several popular libraries that add support for immutability. Check out [immutable-js](https://immutable-js.com)
or [immer](https://immerjs.github.io/immer), for example. I would encourage the use of these in most applications
because immutability generally leads to less error-prone code. However, I'm not going to talk about these here because
they're already well documented and written about elsewhere.

I want to share a simple idea I've been using as a drop-in replacement for `Map` in situations where I don't want to
bloat my workspace with dependencies.

## The Compound Map

In a similar way to the Compound Set linked above, we can define our own Compound Map class as an alternative to the
built-in `Map`. The class should implement the same interface so that it can be used as a straightforward replacement.

The basic idea is to convert the map keys to deterministic strings and use these with the built-in `Map` instead, since
comparison of scalar values behaves as expected.

Here's the class in full (also in [this GitHub Gist](https://gist.github.com/tomcant/4a5b9dc2adddcb6d8bfb084c197c8e81)):

<div class="highlight-filename before">CompoundMap.ts</div>

```ts
export default class CompoundMap<K, V> implements Map<K, V> {
  private readonly items: Map<string, { key: K; value: V }>;

  constructor(entries: [K, V][] = []) {
    this.items = new Map(
      entries.map(([key, value]) => [this.toKey(key), { key, value }])
    );
  }

  clear(): void {
    this.items.clear();
  }

  delete(key: K): boolean {
    return this.items.delete(this.toKey(key));
  }

  get(key: K): V | undefined {
    return this.items.get(this.toKey(key))?.value;
  }

  has(key: K): boolean {
    return this.items.has(this.toKey(key));
  }

  set(key: K, value: V): this {
    this.items.set(this.toKey(key), { key, value });
    return this;
  }

  *[Symbol.iterator](): IterableIterator<[K, V]> {
    for (const [, { key, value }] of this.items) {
      yield [key, value];
    }
  }

  *entries(): IterableIterator<[K, V]> {
    yield* this[Symbol.iterator]();
  }

  *keys(): IterableIterator<K> {
    for (const [, { key }] of this.items) {
      yield key;
    }
  }

  *values(): IterableIterator<V> {
    for (const [, { value }] of this.items) {
      yield value;
    }
  }

  forEach(callbackfn: (value: V, key: K, map: Map<K, V>) => void, thisArg?: any): void {
    for (const [, { key, value }] of this.items) {
      callbackfn.call(thisArg, value, key, this);
    }
  }

  get size(): number {
    return this.items.size;
  }

  get [Symbol.toStringTag](): string {
    return this.constructor.name;
  }

  private toKey(key: K): string {
    return JSON.stringify(key);
  }
}
```

Reworking the example above, we can now make sense of the `points.get()` call:

```ts
import CompoundMap from "./CompoundMap";

const points = new CompoundMap<Point, string>();

points.set({ x: 0, y: 0 }, "The origin");

points.get({ x: 0, y: 0 }); // The origin
```

## Peeking into the Future

As mentioned in the post linked above, there's a potential built-in solution to this problem not too far away. The [Records & Tuples Proposal](https://github.com/tc39/proposal-record-tuple)
aims to introduce deeply immutable data structures, allowing for the following new syntax:

```ts
points.set(#{ x: 0, y: 0 }, "The origin");
```

Notice the `#` symbol preceding the object literal. This is how the proposal intends to signify the object should be
immutable, which would allow for value based equality testing.


This will be a great step forward for the JavaScript spec, but until that happens I'll continue to use `CompoundMap`
(and `CompoundSet`) in situations that don't warrant pulling in larger dependencies.
