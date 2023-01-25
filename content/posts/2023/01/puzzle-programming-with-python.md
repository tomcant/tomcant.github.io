---
title: 'Puzzle Programming with Python'
date: 2023-01-25
---

For the last few years I've been taking part in the [Advent of Code](https://adventofcode.com/) programming contest.
It's been a great way to improve my problem-solving skills and can really aid in getting to grips with new languages.
In 2022 [I chose to solve the puzzles with Python](https://github.com/tomcant/advent-of-code/tree/main/2022/python/solutions), and having enjoyed using the language so much I decided to write about some of the features that I think make it great for this type of programming.

<!--more-->

So, in no particular order...

1. [Comprehension](#comprehension)
2. [Decorator functions](#decorator-functions)
3. [Counter class](#counter-class)
4. [Comparison chaining](#comparison-chaining)
5. [Positive modulo](#positive-modulo)
6. [Floor division](#floor-division)
7. [Negative indices](#negative-indices)

### Comprehension

A comprehension is a language construct used to express items in a list.
For example, here's a list of the first few odd numbers squared:

```python
squares = [n ** 2 for n in range(10) if n % 2 == 1]
```

What I like about this is that it reads more like a definition than a set of instructions for constructing the list.
Here's how we might do the same thing without comprehension:

```python
squares = []
for n in range(10):
    if n % 2 == 1:
        squares.append(n ** 2)
```

Not only is the comprehension more succinct, it also saves us from having to maintain the intermediate states of the list while it's being populated.
In general, avoiding the need to maintain state can help insulate our code from a whole class of tricky bugs.

#### Advent of Code, Day 22 – Monkey Map

A common theme when solving Advent of Code puzzles is navigation through some form of grid.
[Day 22](https://adventofcode.com/2022/day/22) involved reading a grid like the following:

```
        ...#
        .#..
        #...
        ....
...#.......#
........#...
..#....#....
..........#.
        ...#....
        .....#..
        .#......
        ......#.
```

The `#` symbol marks the location of a wall, `.` marks open space and whitespace is out of bounds.
I usually read grids like this into a set or dictionary data structure, depending on the context.
This grid can be parsed into a dictionary with the following comprehension:

```python
grid = {
    (x, y): char
    for y, row in enumerate(raw_grid.splitlines())
    for x, char in enumerate(row)
    if char != ' '
}
```

This gives us all the `(x, y)` coordinates mapped to the characters in those locations, excluding anything that's out of bounds.
We could parse the grid in a number of other ways, but I like this way the most because it feels more robust as a definition than it would as a set of instructions.

### Decorator functions

Python has the ability to decorate functions with other functions, essentially allowing us to enhance their behaviour at runtime.
This can be useful when implementing cross-cutting concerns like logging, timing or caching.

For example, if we wanted to implement function call timing we could define a decorator function like this:

```python
import time

def timer(func):
    def wrap(*args, **named_args):
        t1 = time.time()
        result = func(*args, **named_args)
        t2 = time.time()

        print(f'[timer] "{func.__name__}" took {(t2 - t1):.5f}s')

        return result

    return wrap
```

We can now time how long specific functions take to run:

```python
@timer
def some_func():
    print('running function "some_func"')
    time.sleep(1)
```

Calling `some_func()` gives the following output:

```
running function "some_func"
[timer] "some_func" took 1.00506s
```

Python comes with lots of built-in decorators, and one which I've found to be particularly useful when solving Advent of Code puzzles is `functools.cache`.
Many of the puzzles can be solved using dynamic programming, whereby the original problem is broken down into sub-problems, usually by making a recursive function call.
The key to a performant dynamic programming solution is memoization, which involves caching the answers to sub-problems to avoid repeated computation.

Suppose we have a computationally expensive function call that has a deterministic result based on the values of its parameters.
It doesn't make sense to call this function more than once with the same arguments because the result doesn't change.
The `functools.cache` decorator can enforce this for us:

```python
from functools import cache

@cache
def expensive_func(a, b, c):
    ...
```

As long as the parameters are of hashable types then the `@cache` decorator can build a deterministic key and perform a lookup against past results.
Of course, we could implement this cheaply ourselves and just return early, but this would unnecessarily pollute our code with unimportant details.

Using the decorator is a great example of the language getting out of our way, allowing us to focus on the solution to the problem and nothing else.

#### Advent of Code, Day 19 – Not Enough Minerals

My solution to [Day 19](https://adventofcode.com/2022/day/19) used a recursive depth-first search traversal of a tree.
Each recursive call reflected one of many choices at that position in the tree.
It turned out that many of the branches could be arrived at in more than one way, so it would be wasteful to traverse the tree without checking for precomputed results at each step.

We can leverage the built-in `functools.cache` decorator by using the deterministic attributes of the search as function parameters:

<!-- It would have been simple enough to generate a cache key based on the available attributes at any given point and use that to store results for future lookups. -->
<!-- This reduced the search space because we don't need to compute the result for any given branch more than once. -->

```python
@cache
def search(
    time_left,
    ore=0, clay=0, obsidian=0,
    ore_robots=1, clay_robots=0, obsidian_robots=0
):
    ...
```

The passed arguments form a key that can be used to store the result of each call, ensuring we never do the same work twice.
This optimisation reduces the search space so dramatically that the time taken to solve the problem goes from several hours down to just a few seconds!

### Counter class

Built-in to Python's standard library, `Counter` is a subclass of the dictionary type used for counting hashable objects.
Suppose we want to count occurrences of names, we could initialise a `Counter` as follows:

```python
from collections import Counter

names = Counter(['Alice', 'Bob', 'Charlie', 'Alice'])

print(names) # => Counter({'Alice': 2, 'Bob': 1, 'Charlie': 1})

print(names['Alice']) # => 2
```

The class takes care of counting the given objects based on their values, and a simple API allows us to ask questions like which object is the most common?

```python
names.most_common(1) # => [('Alice', 2)]
```

This makes it perfect for finding the frequencies of characters in a string:

```python
chars = Counter('Puzzle Programming with Python!')

chars.most_common(1) # => [('P', 3)]
```

Since counting is such a common task, `Counter` helps minimise repetitive code, thereby decreasing the likelihood of making mistakes.

#### Advent of Code, Day 23 – Unstable Diffusion

On [Day 23](https://adventofcode.com/2022/day/23) we were given the locations of seeds on an infinite grid:

```
..............
..............
.......#......
.....###.#....
...#...#.#....
....#...##....
...#.###......
...##.#.##....
....#..#......
..............
..............
```

The seeds can't be planted too close together, so using a predefined set of rules for how they should move, we had to determine how long it would take for all seeds to come to a suitable resting spot.

If at any point the rules propose that multiple seeds move to the same location then none of those seeds move.
This is where `Counter` can help.
On each iteration we can build a list of the proposed locations for all seeds and use `Counter` to tell us if we have duplicates:

```python
proposed_locations = apply_rules(current_locations)

counts = Counter(proposed_locations)

for location in proposed_locations:
    if counts[location] == 1:
        # the proposed location is legal
        # so we can move this seed here
```

If I wrote code to count the duplicates myself, it would most likely be less performant and more error-prone than `Counter`.

### Comparison chaining

This feature allows you to express multiple comparisons in a single statement.
For example:

```python
if a < b < c:
    # a < b and b < c
```

The chained expression is more concise than its longer form and reads the same way we are taught to write mathematical expressions, helping reduce cognitive load when reading code.

The expression is still evaluated from left to right, so `a < b` is checked before `b < c`.
This means the logic is still short-circuited at the first inequality and remaining terms will not be evaluated.

In some cases the chained comparison can actually be more performant because each term is guaranteed to be evaluated at most once.
Suppose `b` is an expensive function call, then even though it is present in multiple comparisons, it will only be called once.

The only downside to chained comparisons I can see is that it's easy to abuse them and write conditions that are difficult to read if we are not careful.
For example, this statement is perfectly valid, but horrible for the reader:

```python
if a < b >= c != d == e:
    # a < b and b >= c and c != d and d == e
```

#### Advent of Code, Day 8 – Treetop Tree House

On [Day 8](https://adventofcode.com/2022/day/8) we were required to iterate through a grid of numbers representing the heights of trees in a forest.
Starting from a given `(x, y)` location, iterating towards each edge of the forest looks like this:

```python
for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
    next_x, next_y = x, y

    while 0 <= next_x < max_x and 0 <= next_y < max_y:
        # (next_x, next_y) is within bounds so it's
        # safe to access the grid at that location
        tree_height = forest[next_y][next_x]

        # move on and check the bounds again
        next_x, next_y = next_x + dx, next_y + dy
```

Using this syntax for bounds checking feels very natural and reads clearly.

### Positive modulo

In most languages, the modulo operator, `%`, is an implementation of _remainder_ as defined in the [IEEE 754 standard for floating-point arithmetic](https://en.wikipedia.org/wiki/IEEE_754).
The standard states that the _remainder_ for finite `x` and finite non-zero `y` is the result of `x - n * y`, where `n` is the closest integer to the value of `x / y`.
It also specifies that the sign of the remainder should be the same as the sign of the dividend.
This means the result can be positive or negative.

For example, `5 % 3` is `2` because `5 - round(5/3) * 3` is `5 - 6`, or `-1`.
Since this is negative and the original dividend was positive it must be converted by adding the modulus once: `-1 + 3`.
Hence, in a seemingly convoluted series of calculations we arrive at the final answer of `2`.

Had we started with a negative dividend, `-5 % 3`, then applying the same method we get `-5 - round(-5/3) * 3` is `-5 - (-6)`, or `1`.
Since this is positive and the dividend was negative it must be converted by taking off the modulus once: `1 - 3`, and we arrive at `-2`.

However, the modulo operator in Python does not follow IEEE 754, it does its own thing instead.
The maintainers decided that a negative modulo result isn't as useful as a positive one, hence `-5 % 3` is `1` in Python.

It's easier to see why this would be useful with a less contrived example: suppose we're rotating about a point with `0 <= degrees < 360`.
If we rotate beyond `360` degrees we just use `degrees % 360` to ensure we stay within the range.
If we rotate in the opposite direction, below `0` degrees, we want to wrap around and continue from `360`.
In Python, `-10 % 360` is `350`, as desired.
In languages following IEEE 754, the result would be `-10` and we would have to add `360` to make the result useful.

That's not to say the negative modulo is never useful, so Python provides a function in the standard library for calculating it: `math.remainder()`:

```python
from math import remainder

remainder(-10, 360) # => -10
```

#### Advent of Code, Day 20 – Grove Positioning System

[Day 20](https://adventofcode.com/2022/day/20) involved reorganising a list of around 5,000 numbers.
Each number represented how many steps it had to move in the list; a positive number meant move forward, negative meant move backward.
If a number reaches the start or end of the list then it should wrap around and continue moving.

I used a circular doubly linked list to store the numbers because moving elements around is much more efficient than it would be with a regular list.
Each node in the list keeps a pointer to the next node, so to move a node we must determine what its new next pointer should be.
Once we know this, disconnecting the node and reconnecting it in its new location is trivial.

Here's how we can determine what the new next pointer should be for a given node:

```python
new_next = node.next

for _ in range(node.value % list_length):
    new_next = new_next.next
```

`node.value` could be negative, but since the modulo will always be positive we don't actually need to consider how to move an item backward at all.
Instead, we always move forward, keeping the logic simple without compromising on readability.

### Floor division

The floor division operator, `//`, is syntactic sugar for performing division, rounding down to the nearest whole number and casting the result to an integer.
For example, `5 // 2` is `2`, `17 // 5` is `3`.
In contrast, the regular division operator, `/`, always results in a floating point number, even when the dividend is an exact multiple of the divisor.

Of course, we could just write the functionally equivalent `int(floor(5 / 2))`, but for me, this is all about readability.
The more concise form is much easier to comprehend, especially when it appears in more complex expressions.

Also worth a mention is the semi-related `divmod()` function built into the standard library.
Sometimes it's useful to perform floor division but keep hold of the otherwise disregarded remainder.
For example:

```python
q, r = divmod(17, 5) # => (3, 2)
```

### Negative indices

Nothing groundbreaking, but I thought this was worth a mention because it surprises me that negative indices aren't more prevalent among interpreted languages in general.
Reading from the back of a list can be achieved with `list[-1]`, `list[-2]`, etc.
In most other languages we have to apply a negative offset to the length of the list: `list[len(list)-1]`.

We can also use them when referencing a slice of a list.
Just as `list[1:]` references from the second item to the last, `list[-3:]` references just the last three items.

## Final thoughts

Whilst I've really enjoyed getting to grips with Python, it would be naive of me to think these features are somehow exclusive to the language.
However, I think it's fair to say that finding a language you feel completely content with is extremely rare;
once you've spent enough time with a language you're almost guaranteed to cross something that doesn't agree with your personal taste.
For the most part, though, I've found Python to be pretty satisfying.

My go-to problem-solving language has been JavaScript for a long time, possibly because of its accessibility and ubiquity, but in hindsight it really doesn't lend itself well to the problem-solving domain.
I used to keep a bank of useful JavaScript snippets that I could reproduce as required when solving puzzles, but it turns out most of these are already built into Python (e.g. `Counter`, `defaultdict`, `deque`, `heapq`, `itertools`, `functools`, ...).

None of this is to say that Python is perfect, though.
I haven't even thought about topics like package management or tooling, yet.
In future I might write about how I'd like to see Python change (although probably wishful thinking!).

Going forward I'll be using Python as my problem-solving language of choice.
Onwards to Advent of Code 2023!
