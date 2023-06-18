---
title: Building a Chess AI, Part 1 – Game State
summary: "I've been saying for years that when I get a bit of spare time I'd like to build a chess AI, or [chess engine](https://en.wikipedia.org/wiki/Chess_engine) as it is more commonly known. So a few months ago I set out to do just that and this post is an overview of the project's first major milestone: modelling game state."
date: 2023-03-27
---

- **Part 1 – Game State**
- [Part 2 – Move Generation](/posts/2023/05/building-a-chess-ai-part-2-move-generation/)
- [Part 3 – Evaluation](/posts/2023/06/building-a-chess-ai-part-3-evaluation/)
- Part 4 – Search, coming soon...

I've been saying for years that when I get a bit of spare time I'd like to build a chess AI, or [chess engine](https://en.wikipedia.org/wiki/Chess_engine) as it is more commonly known.
So a few months ago I set out to do just that and this post is an overview of the project's first major milestone: modelling game state.

If you're interested in seeing the full code, check out [tomcant/chess-rs](https://github.com/tomcant/chess-rs) on GitHub.

I had a few high-level goals for the project:

1. Play legal chess.
2. Play sensible chess.
3. Beat me.

The first goal may seem a bit obvious, but this was the hardest and most time-consuming task.
Codifying all the nuances of the rules was painstaking and error-prone, but once this was done, playing _semi_-sensible chess didn't require too much more effort.
And while the engine can beat me, playing _good_ chess may have to be a future aspiration for the project!

Whilst performance wasn't a specific goal, I chose to use Rust because it allows me to express high-level concepts with C-like performance, due to its [zero-cost abstractions](https://doc.rust-lang.org/book/ch13-04-performance.html).

Broadly speaking, the various building blocks of a chess engine (or any two player [zero-sum](https://en.wikipedia.org/wiki/Zero-sum_game) board game) are as follows:

- Game state: storing the board, the pieces, whose turn it is, etc.
- Move generation: finding all the available moves in a position.
- Evaluation: determining who's winning and by how much.
- Search: looking for the best move.

This post will focus on the first topic, but I plan to write about the rest in upcoming posts.

## Foundations

Before getting into the nuts and bolts of game state, I want to highlight a few foundational concepts that can be seen throughout the code: colours, pieces and squares.

### Colours

We need to represent the players.
This will be used to keep track of whose turn it is:

```rust
enum Colour {
    White,
    Black,
}
```

### Pieces

From white pawns to the black king, pieces are abbreviated as follows:

```rust
enum Piece {
    WP, WN, WB, WR, WQ, WK,
    BP, BN, BB, BR, BQ, BK,
}
```

A piece intrinsically has a colour, so it should be cheap to extract this information:

```rust
impl Piece {
    fn colour(&self) -> Colour {
        match self {
            WP | WN | WB | WR | WQ | WK => Colour::White,
            _ => Colour::Black,
        }
    }
}
```

### Squares

From 0 to 63, `a1` to `h8`, squares are value objects composed of unsigned 8-bit integers:

```rust
struct Square(u8);
```

It will be useful to be able to extract a square's zero-based index, file or rank:

```rust
impl Square {
    fn index(&self) -> u8 { self.0 }
    fn file(&self) -> u8 { self.0 & 7 }
    fn rank(&self) -> u8 { self.0 >> 3 }
}
```

We'll see how these foundational concepts evolve as the needs of the engine develop, but for now this provides a good enough base to start thinking about how to represent the board.

## Board Representation

The decisions made this early on have a far-reaching impact on the overall performance of the engine, so it's worth spending time here to ensure the representation is efficient.
For example, it might seem intuitive to use an 8x8 array, but this would have a huge negative impact on performance.
Having to loop over the array and repeatedly check bounds to ensure pieces don't go off the board would really slow down move generation.

### Bitboards

A much more efficient approach is to use [bitboards](https://www.chessprogramming.org/Bitboards).
This takes advantage of the fact that the number of squares on a chessboard and the number of bits in a 64-bit data type are the same, making 64-bit variables a very convenient place to store chess pieces!

Each bit represents the state of one square.
Exactly how the bits map to each square is an implementation detail that changes from engine to engine, but I think it's common to see the following layout:

<style>
  .bitboard {
    width: 95%;
    margin: 1em auto 2em;
    display: grid;
    grid-template-columns: repeat(11, 1fr);
  }
  .bitboard div {
    aspect-ratio: 1;
    display: flex;
    justify-content: center;
    align-items: center;
    text-align: center;
    color: inherit;
  }
  .bitboard .b, .bitboard .w { border: 2px #b58863; border-style: solid none; }
  .bitboard .b { background-color: #b58863; color: #f0d9b5; }
  .bitboard .w { background-color: #f0d9b5; color: #b58863; }
  .bitboard .c { font-weight: bold; }
</style>
<div class="bitboard">
  <div class="c">h8</div><div class="c">g8</div><div class="c">f8</div><div class="c">e8</div><div class="c">d8</div><div></div><div class="c">e1</div><div class="c">d1</div><div class="c">c1</div><div class="c">b1</div><div class="c">a1</div>
  <div class="b">63</div><div class="w">62</div><div class="b">61</div><div class="w">60</div><div class="b">59</div><div>⋯</div><div class="b">4</div><div class="w">3</div><div class="b">2</div><div class="w">1</div><div class="b">0</div>
</div>

It's confusing to visualise the squares with `h8` at the start, but it feels right that `a1` is the least significant bit.
This means that if there's a 1-bit in the 0th index, then there's a piece on `a1`.
It can also be helpful to visualise this as an actual chessboard:

<style>
  .chessboard {
    width: 70%;
    margin: 2em auto 1em;
    display: grid;
    grid-template-columns: repeat(9, 1fr);
  }
  .chessboard div {
    aspect-ratio: 1;
    display: flex;
    justify-content: center;
    align-items: center;
    text-align: center;
  }
  .chessboard :nth-child(9n) { border-right: 2px solid #b58863; }
  .chessboard :nth-child(-n+9) { border-top: 2px solid #b58863; }
  .chessboard .b { background-color: #b58863; color: #f0d9b5; }
  .chessboard .w { background-color: #f0d9b5; color: #b58863; }
  .chessboard .r { border: 2px #b58863; border-style: none solid none none; font-weight: bold; }
  .chessboard .f { border: 2px #b58863; border-style: solid none none; font-weight: bold; }
</style>
<div class="chessboard">
  <div class="r">8</div><div class="w">56</div><div class="b">57</div><div class="w">58</div><div class="b">59</div><div class="w">60</div><div class="b">61</div><div class="w">62</div><div class="b">63</div>
  <div class="r">7</div><div class="b">48</div><div class="w">49</div><div class="b">50</div><div class="w">51</div><div class="b">52</div><div class="w">53</div><div class="b">54</div><div class="w">55</div>
  <div class="r">6</div><div class="w">40</div><div class="b">41</div><div class="w">42</div><div class="b">43</div><div class="w">44</div><div class="b">45</div><div class="w">46</div><div class="b">47</div>
  <div class="r">5</div><div class="b">32</div><div class="w">33</div><div class="b">34</div><div class="w">35</div><div class="b">36</div><div class="w">37</div><div class="b">38</div><div class="w">39</div>
  <div class="r">4</div><div class="w">24</div><div class="b">25</div><div class="w">26</div><div class="b">27</div><div class="w">28</div><div class="b">29</div><div class="w">30</div><div class="b">31</div>
  <div class="r">3</div><div class="b">16</div><div class="w">17</div><div class="b">18</div><div class="w">19</div><div class="b">20</div><div class="w">21</div><div class="b">22</div><div class="w">23</div>
  <div class="r">2</div><div class="w">8</div><div class="b">9</div><div class="w">10</div><div class="b">11</div><div class="w">12</div><div class="b">13</div><div class="w">14</div><div class="b">15</div>
  <div class="r">1</div><div class="b">0</div><div class="w">1</div><div class="b">2</div><div class="w">3</div><div class="b">4</div><div class="w">5</div><div class="b">6</div><div class="w">7</div>
  <div></div><div class="f">a</div><div class="f">b</div><div class="f">c</div><div class="f">d</div><div class="f">e</div><div class="f">f</div><div class="f">g</div><div class="f">h</div>
</div>

The Rust `u64` unsigned integer type will be perfect for this use case.
For example, suppose we have a bitboard with the white king on its start square, `e1`:

```rust
let white_king: u64 = 1 << 4;
```

The value `1 << 4` equates to the binary pattern `10000`, preceded by 59 zeros: a single bit set in the 4th index, which is `e1`.
Now consider the white rooks on `a1` and `h1`:

```rust
let white_rooks: u64 = (1 << 0) | (1 << 7);
```

This looks like `10000001`, preceded by 56 zeros, where the 0th and 7th bits are set.
The actual value of `white_rooks` in this case is 129, or `2^0 + 2^7`, but for the purpose of thinking about the chessboard we needn't worry about actual values.

Consider the black rooks on `a8` and `h8`:

```rust
let black_rooks: u64 = (1 << 56) | (1 << 63);
```

This equates to 9295429630892703744, so it's much simpler to think in terms of indices!

Adding a piece to the board is just a bitwise OR operation to set the desired bit index:

```rust
black_rooks |= (1 << 3); // Put a black rook on d1
```

Removing a piece is a bitwise AND operation with the complement of the desired bit:

```rust
black_rooks &= !(1 << 3); // Remove the black rook on d1
```

We can check for the presence of a piece using another bitwise AND operation:

```rust
if black_rooks & (1 << 63) != 0 {
    // There's a black rook on h8
}
```

Since calculating `1 << index` will be such a common operation, it makes sense to add a method to `Square` to do this for us:

```rust
impl Square {
    fn u64(&self) -> u64 {
        1 << self.0
    }
}
```

An obvious invariant to be guarded by the board representation is that a square can only be occupied by one piece at a time.
It follows that all bitboards must have mutually exclusive bits set, which makes it safe to write the following:

```rust
let white_pieces: u64 =
      white_pawns
    | white_knights
    | white_bishops
    | white_rooks
    | white_queens
    | white_king;

let black_pieces: u64 =
      black_pawns
    | .
    | .
```

This goes to show how memory efficient bitboards are, since the whole state of the board is encoded with just 12 integers.
Compare this with an array based approach, which would use a minimum of 64 values to do the same thing.

With the basic operations outlined above we can define a model of the board that allows us to add/remove pieces and inspect the state of individual squares.
This will provide the basis for the rest of the engine to query and mutate the state of the game.

### Implementing Bitboards

I defined a `Board` structure to store the 12 piece bitboards:

```rust
struct Board {
    pieces: [u64; 12],
    colours: [u64; 2],
}
```

Additionally, tracking pieces by colour will make it easy to determine the occupancy of all squares, since we can just merge the 2 colour bitboards:

```rust
impl Board {
    fn occupancy(&self) -> u64 {
        self.colours[Colour::White] | self.colours[Colour::Black]
    }
}
```

This gives us a new bitboard with the locations of all pieces, making it easy to check if a given square has a piece on it:

```rust
impl Board {
    fn has_piece_at(&self, square: Square) -> bool {
        self.occupancy() & square.u64() != 0
    }
}
```

Determining _which_ piece is more complicated because we can't avoid looping over the piece bitboards:

```rust
impl Board {
    fn piece_at(&self, square: Square) -> Option<Piece> {
        Piece::pieces().find(|&&piece| {
            self.pieces[piece] & square.u64() != 0
        })
    }
}
```

Adding and removing pieces simply follows the bitwise logic described above:

```rust
impl Board {
    fn put_piece(&mut self, piece: Piece, square: Square) {
        self.pieces[piece] |= square.u64();
        self.colours[piece.colour()] |= square.u64();
    }

    fn remove_piece(&mut self, square: Square) {
        let Some(piece) = self.piece_at(square) else {
            return;
        };
        self.pieces[piece] &= !square.u64();
        self.colours[piece.colour()] &= !square.u64();
    }
}
```

These few methods provide enough functionality to start working with the board in a meaningful way.
We'll go on to use this structure as the foundation for move generation.

### The Bigger Picture

If you're familiar with [FEN](https://en.wikipedia.org/wiki/Forsyth%E2%80%93Edwards_Notation), you'll know that the board is only part of the story.
FEN is a format used to describe the state of a game at a single point in time.
For example, consider the start position as a FEN string:

```
                    the                  colour
                   board                 to move   en-passant square
                     |                      |      |
                     |                      |      |
                     v                      v      v
rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 <-- move counters
        ^                         ^            ^
        |                         |            |
        |                         |            |
      black                     white       castling
      pieces                    pieces       rights
```

The model we have so far only includes the board, so we're missing a few things:

- Whose turn it is
- Castling rights
- The en-passant square, if any
- The half and full move counters

I didn't feel like all this belonged inside `Board` (which FEN sort of indicates), so I created a separate structure to keep it alongside the board, instead:

```rust
struct Position {
    board: Board,
    colour_to_move: Colour,
    castling_rights: CastlingRights,
    en_passant_square: Option<Square>,
    half_move_clock: u8,
    full_move_counter: u8,
}
```

This structure reflects the FEN string above.
I think moving forwards there could be a need to expand upon this and store more information for use in search optimisation ([transposition tables](https://en.wikipedia.org/wiki/Transposition_table) and [zobrist hashing](https://en.wikipedia.org/wiki/Zobrist_hashing)), but this should be good enough for now.

#### Castling Rights

The last thing worth mentioning is the `CastlingRights` type, which stores the sides of the board each colour has the right to castle on:

```rust
struct CastlingRights(u8);
```

The wrapped `u8` ranges from 0 to 15 using a combination of the following values:

```rust
enum CastlingRight {
    WhiteKing = 1,
    WhiteQueen = 2,
    BlackKing = 4,
    BlackQueen = 8,
}
```

When both colours can castle on either side, the castling rights are 15 (1 + 2 + 4 + 8).
Using powers of two like this, we can work with castling rights in the same way as a bitboard:

```rust
impl CastlingRights {
    fn none() -> Self {
        Self(0)
    }

    fn has(&self, right: CastlingRight) -> bool {
        self.0 & right as u8 != 0
    }

    fn add(&mut self, right: CastlingRight) {
        self.0 |= right as u8;
    }

    fn remove(&mut self, right: CastlingRight) {
        self.0 &= !(right as u8);
    }
}
```

This allows us to write the following:

```rust
let mut rights = CastlingRights::none();

rights.add(BlackQueen);

assert!(rights.has(BlackQueen));

rights.remove(BlackQueen);
```

Similarly to bitboards, this is an efficient way to model castling rights because querying and mutating the state with bitwise operations is fast.
We'll see how the engine uses the structure more meaningfully in a future post, when making and unmaking moves in a `Position`.

## Next Up: Move Generation

This post covered how the engine models game state, which was the first milestone for the project.
In the next post I'll write about move generation: finding all the available moves in a position.
This will require expanding on the use of bitboards to calculate which squares are under attack, and we'll see a couple of approaches for effectively testing move generation.

♟️
