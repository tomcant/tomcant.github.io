---
title: "Introduction to Pathfinding with Mazes and Breadth-first Search"
date: 2021-09-13
draft: false
mermaid: true
---

As with many programmers wanting to sharpen their problem-solving skills, I've recently been tackling [Advent of Code](https://adventofcode.com),
a digital Advent calendar in which each day presents an increasingly difficult puzzle to solve. Having completed the
2016 calendar, which [involved](https://adventofcode.com/2016/day/11) [several](https://adventofcode.com/2016/day/13)
[pathfinding](https://adventofcode.com/2016/day/22) [problems](https://adventofcode.com/2016/day/24), I've become
obsessed with mazes and pathfinding algorithms.

<!--more-->

This post is an introduction to pathfinding with mazes and breadth-first search, the algorithm that forms the basis of
pathfinding in general. I'll use TypeScript for the code, but all the ideas will be language agnostic.

At a high level, pathfinding requires two things: a model of the search space (the maze in this case), and a way to
search through the possible paths that can be taken. That's a pretty dramatic simplification, so let's break it down.

## Modelling the Maze

An obvious approach is to use a 2D array to model the maze as a grid. This feels quite natural, but it's not very space
efficient. Imagine a 10x10 maze with no walls. That's 100 array items to define an empty maze! Another approach is to
only store the size of the maze along with the (x, y) coordinates of the walls. An empty MxN maze is now just two
numbers. Much better!

One of the basic building blocks of this approach will be our model of an (x, y) coordinate. We could use a plain old
JavaScript object like `{ x: 1, y: 1 }`, but since we'll be using this in lots of places I think it deserves to be
treated like a first-class citizen. We'll write a class for this called `Vec2d` with a couple of methods that will come
in handy later:

```ts
class Vec2d {
  constructor(
    readonly x: number,
    readonly y: number
  ) {}

  public add(v: Vec2d): Vec2d {
    return new Vec2d(this.x + v.x, this.y + v.y);
  }

  public equals(v: Vec2d): boolean {
    return this.x === v.x && this.y === v.y;
  }
}
```

The maze itself is a class with properties for its width and height, and a [Set](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Set)
of `Vec2d` for the positions of the walls:

```ts
class Maze {
  private walls: Set<Vec2d>;

  public constructor(
    readonly width: number,
    readonly height: number,
    walls: Vec2d[] = []
  ) {
    this.walls = new Set(walls);
  }

  public isWall(pos: Vec2d): boolean {
    return this.walls.has(pos);
  }
}
```

Before we can start searching through the maze, we need a way to find the available squares from any given position. A
square is available if it's not a wall and is within the bounds of the maze. Using a list of `Vec2d` to represent the
four directions of travel, we can write a utility function as follows:

```ts
const DIRECTIONS = [
  new Vec2d(1, 0),
  new Vec2d(0, 1),
  new Vec2d(-1, 0),
  new Vec2d(0, -1),
];

const getNeighbours = (maze: Maze, pos: Vec2d): Vec2d[] =>
  DIRECTIONS
    .map((dir) => pos.add(dir))
    .filter((pos) => !maze.isWall(pos))
    .filter(
      (pos) =>
        pos.x >= 0 && pos.x < maze.width &&
        pos.y >= 0 && pos.y < maze.height
    );
```

Next up, we need a way to search through all the possible paths in the maze.

## Introducing Breadth-first Search

The idea is simple: given a starting position, we explore the surrounding squares one step at a time in every direction.
Eventually, either the target comes into range or we run out of places to look.

Squares should be explored in order of their distance from the start. For each square, we make a note of its neighbours
and only explore them once all previously encountered squares have been visited.

We can achieve this idea with [the Queue data structure](https://en.wikipedia.org/wiki/Queue_(abstract_data_type)). We
take squares to explore from the front of the queue and add squares for later to the back. The following flow diagram
shows how the algorithm works:

<style>
  img {
    margin: 0 auto 1rem;
  }
  .mermaid {
    margin-bottom: 1.5rem;
    text-align: center;
  }
</style>

{{<mermaid>}}
%%{ init: { 'themeVariables': { 'fontSize': '0.8rem' }}}%%
flowchart TD
  A(Add start\nsquare to queue) --> B{Is queue\nempty?}
  B --->|Yes| G(No path\nexists)
  B -->|No| C(Dequeue\nnext square)
  C --> D{Already\nvisited?}
  D -->|Yes| B
  D -->|No| E(Mark as visited)
  E --> F{Is this\nthe target?}
  F ==>|Yes| H(Found the\nshortest path!)
  F -->|No| I(Enqueue\nneighbouring\nsquares)
  I --> B
  classDef default stroke:#2f363d
  style H stroke-width:3px
{{</mermaid>}}

Using the queue implementation I posted in [Queueing with TypeScript](/posts/2021/08/queueing-with-typescript/),
translating this process to code could look something like this:

```ts
function breadthFirstSearch(
  maze: Maze,
  startPos: Vec2d,
  targetPos: Vec2d
) {
  const queue = new Queue<Vec2d>();
  queue.enqueue(startPos);

  const visited = new Set<Vec2d>();

  while (!queue.isEmpty()) {
    const currentPos = queue.dequeue();

    if (visited.has(currentPos)) {
      continue;
    }

    visited.add(currentPos);

    if (currentPos.equals(targetPos)) {
      // Found the shortest path!
      return;
    }

    queue.enqueue(...getNeighbours(maze, currentPos));
  }

  // If we end up here then no path exists
}
```

### Checkpoint!

This covers the basics of breadth-first search. We have a model of the search space and a means of searching through it.
If a path exists between the given start and target positions then our function will find it.

A nice property of this algorithm is that when the target is found, we're guaranteed to have the shortest path. However,
our current implementation isn't all that useful because we haven't actually produced the path anywhere. Ideally, our
function would return the shortest path as a list of `Vec2d`, and this can be achieved without much more effort.

### Returning the Shortest Path

When the target is found, we can construct the shortest path by retracing our steps back to the start. The simplest way
to do this is to add a reference to the previous square into each queue item. Instead of only queueing the positions of
squares to explore, we'll create a new type to store a position and a reference, and queue that instead.

```ts
type SearchNode = {
  pos: Vec2d;
  prev?: SearchNode;
};
```

We can think of this like a linked list in reverse, with the start position at one end and the target at the other. All
we need to do is follow the references backwards from the target and make a note of each `Vec2d` along the way. A simple
function to do this is as follows:

```ts
function rewindPath(node: SearchNode): Vec2d[]
{
  const path = [];

  while (node.prev) {
    path.unshift(node.pos);
    node = node.prev;
  }

  return path;
}
```

We should call this function as soon as we find the target. Here's the original search function modified to return the
shortest path:

{{<highlight ts "hl_lines=24">}}
function breadthFirstSearch(
  maze: Maze,
  startPos: Vec2d,
  targetPos: Vec2d
): Vec2d[] {
  const queue = new Queue<SearchNode>();

  // `prev` is initially undefined
  queue.enqueue({ pos: startPos });

  const visited = new Set<Vec2d>();

  while (!queue.isEmpty()) {
    const node = queue.dequeue();

    if (visited.has(node.pos)) {
      continue;
    }

    visited.add(node.pos);

    if (node.pos.equals(targetPos)) {
      // Found the shortest path!
      return rewindPath(node);
    }

    for (const neighbour of getNeighbours(maze, node.pos)) {
      queue.enqueue({ pos: neighbour, prev: node });
    }
  }

  throw new Error("No path exists!");
}
{{</highlight>}}

## Putting It All Together

We now have the components required to find the shortest path between two points in a maze. The following simple
function call returns the shortest path from top-left to bottom-right in an empty 10x10 grid:

```ts
breadthFirstSearch(
  new Maze(10, 10),
  new Vec2d(0, 0),
  new Vec2d(9, 9)
);
```

However, the empty grid doesn't make for a very interesting maze! This would be much better with a few walls as
obstacles. As it turns out, it's not too much more work to draw a grid using basic HTML elements to reflect the state of
a `Maze`, and from there it's straightforward enough to allow adding walls with mouse events.

Below is a demo of [a project I built](https://tomcant.dev/pathfinder) as a visual aid to exploring pathfinding.
Generate a maze and/or click _Search_ to see how the algorithm works. Draw walls and move the start/target to see how it
behaves in different scenarios.

<iframe id="bfs-demo" width="100%" height="370px"></iframe>
<script>
  const cols = Math.floor(document.querySelector('.post').clientWidth / 24);
  document.querySelector('#bfs-demo').src = `https://tomcant.dev/pathfinder/?embed&rows=13&cols=${cols}`;
</script>

## JavaScript's Mutability Model: a Help or a Hindrance?

Before finishing up, I need to address a glaring problem with the code in this post. In an ideal world, the `Vec2d`
class would be a value object, where its identity is defined by the values of its (x, y) properties. However, JavaScript
makes this difficult. For example...

```ts
new Vec2d(1, 1) === new Vec2d(1, 1); // False!
```

It's hard to think of a context in which this condition should fail, but in JavaScript, it will never pass. The reason
is that JavaScript compares objects by reference rather than by value, and this is a pretty big problem for our
pathfinding code.

We use the built-in `Set` class to keep track of squares we've visited, so we can make sure we don't try to visit the
same square twice. For example...

```ts
const visited = new Set<Vec2d>();
visited.add(new Vec2d(1, 1));
```

The algorithm now knows it has already visited `(1, 1)`. Or so you would think! In fact, the following line produces an
unexpected result:

```ts
visited.has(new Vec2d(1, 1)); // False!
```

Although `Vec2d` has an `equals()` method for checking equality by value, there's no way of telling JavaScript to use it
when making comparisons.

There's some promising discussion in the JavaScript community around solving this. The [Records & Tuples Proposal](https://github.com/tc39/proposal-record-tuple)
aims to introduce immutable data structures that support object comparison by value, but until then we'll have to handle
this some other way.

A possible workaround is to convert the `Vec2d` object to a `string` and store that instead, since comparison of scalar
values behaves as expected. We could add a `toString()` method and call it before checking if a square has been visited,
but this would bloat the code and detract from the real problem.

A better approach is to use a [Compound Set](https://eddmann.com/posts/implementing-a-compound-set-in-typescript/),
which works just like the built-in `Set`, except that entries are automatically converted to deterministic strings, and
can therefore be compared by value. This makes the `visited.has()` check above work as expected and keeps our code clean
by hiding the problem behind a clever abstraction.

Happy pathfinding!
