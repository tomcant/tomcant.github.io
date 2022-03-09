---
title: "Queueing with TypeScript"
date: 2021-08-05
draft: false
---

I've recently spent more time than I'd like to admit solving programming puzzles, and the queue data structure seems to
be a reoccurring theme. JavaScript doesn't have a built-in implementation, so I find myself copy/pasting the same few
lines of code everywhere. I've decided it's time to put that snippet somewhere more accessible.

<!--more-->

I could just use the built-in array type directly with its `push()` and `shift()` methods, but that would be boring! I
prefer to make the queue a first-class citizen in its own right. The idea is to hide the specific implementation details
of "push" and "shift" behind more queue-like terminology: "enqueue" and "dequeue". This makes the resultant code easier
to read because the intentions are clearer.

<div class="highlight-filename before">Queue.ts</div>

```ts
export default class Queue<T> {
  constructor(private items: T[] = []) {}

  public enqueue(...items: T[]): void {
    this.items.push(...items);
  }

  public dequeue(): T {
    if (this.isEmpty()) {
      throw new Error("No items to dequeue!");
    }

    return this.items.shift() as T;
  }

  public isEmpty(): boolean {
    return this.size === 0;
  }

  public get size(): number {
    return this.items.length;
  }
}
```

Example usage:

```ts
import Queue from "./Queue";

const q = new Queue<string>();

console.assert(q.isEmpty());

q.enqueue("First item", "Second item");
q.enqueue("Another item");

console.assert(q.size === 3);

console.log(q.dequeue()); // "First item"

console.assert(q.size === 2);
```
