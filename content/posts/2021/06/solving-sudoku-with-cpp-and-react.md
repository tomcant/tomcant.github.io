---
title: Solving Sudoku with C++, WASM and React
description: 
date: 2021-06-30
draft: false
---

In a [previous post](/blog/posts/2021/04/running-cpp-in-a-web-browser-with-webassembly/) I talked about rebuilding some
old C++ projects with WebAssembly and running them in a web browser. One such project was a Sudoku solver, and I want to
share some recent progress in this post.

<!--more-->

Check out [the GitHub repo](https://github.com/tomcant/sudoku-solver) if you're interested in seeing the full code. I've also
included a demo of the transformed app below.

The original project was a command-line program which read a puzzle from `stdin` and printed the solution or an error
message to `stdout`. Such a simple flow translates to the web quite easily; the puzzle can come from user input and can
be output with basic HTML elements.

## Goals

1. To solve a Sudoku puzzle by interacting with a C++ program from JavaScript.
2. To provide a UI for displaying, editing and solving a Sudoku puzzle.

Another loose goal was to only change the original code where absolutely necessary, since it's interesting to see how
much of the original codebase really needs to change to get it working in a browser.

## Interacting with C++ from JavaScript

At a high level, the solver is made of two parts: a representation of the puzzle, and a function that returns the solved
representation for a given puzzle if it exists. It's these components of the original C++ that need exposing to the
browser.

In the previous post I showed how it's possible to expose C++ to JavaScript using Emscripten. I used a JavaScript method
called `cwrap()` which allowed me to call a function defined in C++, but I can't use that here because the solver code
is object oriented. The good news is that Emscripten provides a much more powerful tool for defining what to expose:
[Embind](https://emscripten.org/docs/porting/connecting_cpp_and_javascript/embind.html).

With Embind, I'm able to expose classes, structs, functions, enums, constants, and pretty much anything else that can be
defined in C++. In my use case, I need to expose two classes, `Grid` and `Solver`:

<div class="highlight-filename before">wasm-bindings.cc</div>

```cpp
#include <emscripten/bind.h>
#include "solver.h"

using sudoku::Grid;
using sudoku::Solver;

EMSCRIPTEN_BINDINGS(Grid) {
  emscripten::class_<Grid>("Grid")
    .function("ToString", &Grid::ToString)
    .class_function("FromString", &Grid::FromString);
}

EMSCRIPTEN_BINDINGS(Solver) {
  emscripten::class_<Solver>("Solver")
    .class_function("Solve", &Solver::Solve);
}
```

**Note:** I had to invoke the `emcc` compiler with `--bind` to access `bind.h`.

This exposes the following methods:

- `Grid::ToString()` &ndash; grids will be stored as strings of digits in JavaScript
- `Grid::FromString()` &ndash; a static constructor method for creating a new `Grid`
- `Solver::Solve()` &ndash; this goes without saying!

These are now callable in the browser via the Emscripten `Module` object, similar to what we saw in
the previous post:

```js
const grid = Module.Grid.FromString('... 81 digit string ...');
const solvedGrid = Module.Solver.Solve(grid);

console.log(solvedGrid.ToString());
```

This achieves the first goal of the project: to solve a Sudoku puzzle by interacting with a C++ program from JavaScript
:tada:

## Unsolvable Puzzles

The algorithm used by the solver isn't particularly clever. It's a brute force depth-first search, so as long as the
given puzzle has a solution, the only thing standing in the way of finding it is time. But what happens when a solution
doesn't exist? Perhaps controversially, the solver throws an exception...

### Exception Handling

Whether this should be considered a runtime error is up for debate, but this demonstrates how exceptions thrown by C++
can be caught and handled with JavaScript.

<div class="highlight-filename before">solver.cc</div>

```c++
struct Unsolvable : public std::runtime_error {
  Unsolvable() : std::runtime_error("Grid is not solvable") {}
};

throw Unsolvable(); // Doh!
```

Emscripten allows us to use JavaScript's built-in `try...catch`:

```js
try {
  const grid = Module.Grid.FromString('...');
  const solvedGrid = Module.Solver.Solve(grid);

  console.log(solvedGrid.ToString());
} catch (error) {
  console.error(error);
}
```

This seems simple enough, but `error` is actually a number here, rather than the expected message or exception
object. This happens because the exception is thrown from WASM using a pointer instead of a copy of the thrown object,
so the number we're given represents the location in memory where we can find the exception.

To make use of the pointer we need to expose another C++ function:

<div class="highlight-filename before">wasm-bindings.cc</div>

```cpp
std::string getExceptionMessage(intptr_t ptr) {
  return std::string(reinterpret_cast<std::exception *>(ptr)->what());
}

EMSCRIPTEN_BINDINGS(getExceptionMessage) {
  emscripten::function("getExceptionMessage", &getExceptionMessage);
}
```

The `getExceptionMessage()` function takes a number representing a pointer and treats it as a `std::exception` pointer
instead, allowing us to call the `what()` method to retrieve the original message.

We can now do something useful with `error`:

```js
try {
  ...
} catch (error) {
  console.error(Module.getExceptionMessage(error));
}
```

**Note:** by default Emscripten compiles with exception catching disabled, so if the C++ program throws an exception
that's not caught by the program itself, it terminates. Invoke the `emcc` compiler with the
`NO_DISABLE_EXCEPTION_CATCHING` option to enable this behaviour.

## Building a User Interface

I'll start by saying that I have about as much creativity as a pile of damp napkins. That being said, it shouldn't
be too hard to cobble together something that roughly resembles Sudoku.

The end result must provide the following capabilities:

- display an editable Sudoku grid
- choose from a predefined list of puzzles
- solve the given puzzle and display the solution.

This roughly maps to 81 `<input>` elements, a `<select>` and a `<button>`.

### Enter React

I chose React because it allows me to focus on Sudoku, rather than on wrangling the browser DOM into shape. With its
declarative nature I only have to worry about the internal state of the app and how it changes in response to user
interaction. React takes care of the rest and eliminates a whole class of developer headaches.

Fortunately, the app is extremely simple. I only need to keep track of the digits in the grid and any error returned by
the solver. As mentioned above, the grid will be stored in JavaScript as a string of length 81; one character
per grid cell. Empty grid cells will be represented as zeroes to make life easy, since then all positions in the string
are digits and can be treated the same.

The predefined puzzles are as follows:

```js
const puzzles = {
  easy: '050000030302000704080010050000703000006050300000802000020090040609000801010000060',
  medium: '300400600700090003800300000030521000000000090020030040048002000006000100000007400',
  hard: '800000000003600000070090200050007000000045700000100030001000068008500010090000400',
};
```

We'll use the _"easy"_ puzzle and no error as the initial state:

```jsx
const [cells, setCells] = React.useState(puzzles.easy);
const [error, setError] = React.useState(null);
```

<small>_(Fun fact: according
[to](https://metro.co.uk/2012/06/28/worlds-hardest-sudoku-everest-created-by-mathematician-arto-inkala-483588/)
[a](https://www.quora.com/What-is-the-toughest-sudoku-in-world)
[few](https://abcnews.go.com/blogs/headlines/2012/06/can-you-solve-the-hardest-ever-sudoku)
[sources](https://www.telegraph.co.uk/news/science/science-news/9359579/Worlds-hardest-sudoku-can-you-crack-it.html),
the "hard" puzzle shown here is generally regarded as the hardest puzzle ever created, designed in 2012 by Finnish
mathematician Arto Inkala)_</small>

### Component Architecture

Now we know what the state looks like, we need a place to put it. In React speak, the app is made of three components:
`Solver`, `Controls` and `Grid`, arranged as follows:

```jsx
<Solver>
  <Controls />
  <Grid />
</Solver>
```

It would be reasonable to assume the state should live in `Grid` since that's where the digits belong visually, but this
could make things tricky later. In general, state should be ["lifted"](https://reactjs.org/docs/lifting-state-up.html)
to the closest common ancestor of all the components that need it.

While it's clear that `Grid` needs the state (to display the puzzle!), it's not so obvious with `Controls`. Remember
that `<select>` element? This changes the puzzle displayed on the grid, so the component needs to be aware of the state
if only to update it. The state therefore lives in `Solver` and can be fed down to the child components as necessary.

I want to avoid passing the `setCells()` function directly to a child component because this unnecessarily widens the
scope for mutating the state; something feels wrong with that. The ideal solution would be for the parent component to
pass down a set of behaviours it deems to be safe for the child component to use. This feels better because we haven't
violated encapsulation of the parent component's internals.

The most natural way to achieve this is for `Solver` to define a closure for each behaviour:

```jsx
const Solver = () => {
  const [cells, setCells] = React.useState(puzzles.easy);
  const [error, setError] = React.useState(null);

  const setPuzzle = (puzzle) => {
    setCells(puzzles[puzzle]);
  };

  const solvePuzzle = () => {
    try {
      const grid = Module.Grid.FromString(cells);
      const solvedGrid = Module.Solver.Solve(grid);

      setCells(solvedGrid.ToString());
    } catch (error) {
      setError(Module.getExceptionMessage(error));
    }
  };

  const setCell = (idx, digit) => {
    const newCells = [...cells];
    newCells[idx] = digit || '0';
    setCells(newCells.join(''));
  };

  return (
    <>
      <Controls setPuzzle={setPuzzle} solvePuzzle={solvePuzzle} />
      <Grid cells={cells} setCell={setCell} />
      {error && <p>{error}</p>}
    </>
  );
};
```

The `Controls` and `Grid` components bring these behaviours to life:

```jsx
const Controls = ({ setPuzzle, solvePuzzle }) => (
  <>
    <select onChange={(e) => setPuzzle(e.target.value)}>
      <option value="easy">Easy</option>
      <option value="medium">Medium</option>
      <option value="hard">Hard</option>
    </select>
    <button onClick={solvePuzzle}>Solve</button>
  </>
);

const Grid = ({ cells, setCell }) => (
  [...cells].map((cell, idx) => (
    <input
      type="text"
      value={Number(cell) || ''}
      onChange={(e) => setCell(idx, e.target.value)}
      className="Grid-square"
    />
  ))
);
```

The second goal of the project is complete: to provide a UI for displaying, editing and solving a Sudoku puzzle
:tada:

## Wrapping Up

I was surprised at how straightforward it was to transform this old C++ program into a web app. I mentioned that a loose
goal was to change the original code as little as possible, and I think I've gotten away quite lightly with this. Aside
from the `wasm-bindings.cc` file (which is kind of a necessity) I only had to add a couple of methods to the `Grid`
class for handling conversion to and from a string.

I'm hoping to find more time in the future to extend the project by visualising the steps the solver took to reach the
solution, and perhaps by adding a feature for generating puzzles (although that feels like a different problem
altogether).

It's been a fun side project to work on, mainly because it's fun playing with technologies I wouldn't otherwise get to
use (particularly WASM), but also because I got to learn a tonne about React along the way.

<iframe id="solver" src="https://tomcant.dev/sudoku-solver/?embed" width="100%" height="570px"></iframe>
