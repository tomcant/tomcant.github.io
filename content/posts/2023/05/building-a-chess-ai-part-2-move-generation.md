---
title: Building a Chess AI, Part 2 – Move Generation
summary: "In my last post [I wrote about modelling game state](/posts/2023/03/building-a-chess-ai-part-1-game-state/), the first milestone of a project I've been working on to build a chess engine in Rust. In this post I'm going to write an overview of the second milestone: move generation."
date: 2023-05-14
---

- [Part 1 – Game State](/posts/2023/03/building-a-chess-ai-part-1-game-state/)
- **Part 2 – Move Generation**
- [Part 3 – Evaluation](/posts/2023/06/building-a-chess-ai-part-3-evaluation/)
- Part 4 – Search, coming soon...

In my last post [I wrote about modelling game state](/posts/2023/03/building-a-chess-ai-part-1-game-state/), the first milestone of a project I've been working on to build a chess engine in Rust.
In this post I'm going to write an overview of the second milestone: move generation.

If you're interested in seeing the full code, check out [tomcant/chess-rs](https://github.com/tomcant/chess-rs) on GitHub.

So far we have a few types to represent some of the game's basic concepts: colours, pieces and squares, and a model of the board that uses bitboards to track the locations of pieces.

The approach I've taken to generating moves is to calculate a bitboard of all the squares under attack for each of the colour-to-move's pieces, and convert each of these to a list of moves.
Combining these into one list produces the majority of moves in a position, leaving just a handful of "special" cases like castling and en-passant.

The main topics to cover are:

1. using bitboards to calculate "attack squares",
2. handling "special" cases with bitboards,
3. converting bitboards to moves, and
4. verifying correctness with [perft](https://www.chessprogramming.org/Perft).

## Calculating Attack Squares

At the heart of the move generator is a simple looking function for calculating attacks:

```rust
fn get_attacks(piece: Piece, square: Square, board: &Board) -> u64 {
    match piece {
        WP | BP => get_pawn_attacks(...),
        WN | BN => get_knight_attacks(...),
        WB | BB => get_bishop_attacks(...),
        WR | BR => get_rook_attacks(...),
        WQ | BQ => get_bishop_attacks(...) | get_rook_attacks(...),
        WK | BK => get_king_attacks(...),
    }
}
```

Given a piece and a square, this returns a bitboard containing all the squares under attack by that piece.
We can then convert this bitboard into a list of moves and continue with the next piece.

### Sliding Piece Attacks

Bishops, rooks and queens all slide along their paths for as long as there isn't another piece blocking the way.
This is different from non-sliding pieces where the squares under attack are always known upfront, and so we require different approaches.

There are lots of popular methods for calculating sliding piece attacks using bitboards.
As a starting point I implemented the simplest method I could find: [the classical approach](https://www.chessprogramming.org/Classical_Approach).

Consider a bishop on `c3` with no blocking pieces:

<div id="bishop-attack-rays"></div>

We can construct a bitboard from the highlighted squares and use it any time we need the attacks for a bishop on `c3`.
However, if pieces block the path then we'd need to figure out which squares are actually reachable first.
Take the following position for example:

<div id="bishop-with-blockers"></div>

We need to determine that `g7` and `h8` should be excluded from the bishop's attacks.
One approach is to iterate over the bishop's path until we hit a piece, but this would be slow because we'd be querying the state of the board _a lot_.

Instead, if we take the bishop's path and perform a bitwise AND operation with all the pieces on the board, we get the following:

<div class="chessboard-bitwise-calc">
  <div id="bishop-attack-ray"></div>
  <div><strong>AND</strong></div>
  <div id="occupancy"></div>
  <div><strong>=</strong></div>
  <div id="bishop-attack-blockers"></div>
</div>

This tells us where the blocking pieces are.
Next, we perform bitwise XOR with just the section of path after the first blocking square:

<div class="chessboard-bitwise-calc">
  <div id="bishop-attack-ray2"></div>
  <div><strong>XOR</strong></div><!-- ⌃ -->
  <div id="occupancy2"></div>
  <div><strong>=</strong></div>
  <div id="bishop-attack-blockers2"></div>
</div>

This gives the attack squares for the bishop taking into account the pieces that block its path.
Repeating for each direction yields the complete bitboard of attack squares.

Here's what it looks like in code:

```rust
enum BishopDirection {
  NW, NE, SW, SE,
}

fn get_bishop_attacks(square: Square, board: &Board) -> u64 {
    let mut attacks = 0;

    for direction in [NW, NE, SW, SE] {
        let path = BISHOP_ATTACKS[square][direction];
        let blockers = path & board.occupancy();

        if blockers == 0 {
            // No blockers in this direction so
            // add the whole path and move on.
            attacks |= path;
            continue;
        }

        let first_blocking_square = match direction {
            NW | NE => Square::first(blockers),
            SW | SE => Square::last(blockers),
        };

        attacks |= path ^ BISHOP_ATTACKS[first_blocking_square][direction];
    }

    attacks
}
```

Notice the use of `BISHOP_ATTACKS`, a pre-calculated array of 64 x 4 bitboards indexed by square and direction.
This is used to look up the squares a bishop can attack on an empty board and means we only have to calculate this once.

#### Finding the first blocking square

I want to highlight how the first blocking square calculation works because it's not obvious from the code above.
When the bishop's path points north-east or north-west, the first blocker is always the first 1-bit in the blockers bitboard, which is just the number of trailing zeros:

```rust
impl Square {
    fn first(squares: u64) -> Self {
        Self(squares.trailing_zeros())
    }
}
```

{{<highlight rust "hl_lines=2">}}
let first_blocking_square = match direction {
    NW | NE => Square::first(blockers),
    SW | SE => Square::last(blockers),
};
{{</highlight>}}

<div class="chessboard-grid-double">
  <div id="bishop-attack-ray-blocker-nw"></div>
  <div id="bishop-attack-ray-blocker-ne"></div>
</div>

Conversely, when there are blockers on a south-east or south-west path then the first blocker is always the _last_ 1-bit, so we identify it by the number of _leading_ zeros instead.
A simple calculation is then used to flip its orientation:

```rust
impl Square {
    fn last(squares: u64) -> Self {
        Self(63 - squares.leading_zeros())
    }
}
```

{{<highlight rust "hl_lines=3">}}
let first_blocking_square = match direction {
    NW | NE => Square::first(blockers),
    SW | SE => Square::last(blockers),
};
{{</highlight>}}

<div class="chessboard-grid-double">
  <div id="bishop-attack-ray-blocker-sw"></div>
  <div id="bishop-attack-ray-blocker-se"></div>
</div>

The engine uses the same logic for generating rook attacks, and by combining this and bishop attacks together we get queen attacks.

This is the simplest method for calculating sliding piece attacks.
There are [several much more efficient methods](https://www.chessprogramming.org/Sliding_Piece_Attacks), but I wanted to keep things simple to start with.

### Non-sliding Piece Attacks

In contrast, pawns, knights and kings only attack a fixed set of their surrounding squares, and determining which ones is much easier because we don't have to deal with blocking pieces.

We can use something like this to generate a bitboard of squares attacked by the king:

```rust
let king_attacks: u64 =
      king_square << 8  // north
    | king_square >> 8  // south

    | king_square << 1  // east
    | king_square >> 1  // west

    | king_square << 7  // north-west
    | king_square << 9  // north-east

    | king_square >> 7  // south-east
    | king_square >> 9; // south-west
```

Bear in mind that left-shifting moves a square towards the top of the board and right-shifting moves it towards the bottom:

<style>
#king-attacks .chessboard-21da3 { width: 80%; }
@media (min-width: 48em) { #king-attacks .chessboard-21da3 { width: 65%; } }
#king-attacks .chessboard-21da3 .square-highlight:after { font-size: smaller; white-space: nowrap; }

#king-attacks .chessboard-21da3 .square-highlight[data-square-coord="c6"]:after { content: "<< 7"; }
#king-attacks .chessboard-21da3 .square-highlight[data-square-coord="d6"]:after { content: "<< 8"; }
#king-attacks .chessboard-21da3 .square-highlight[data-square-coord="e6"]:after { content: "<< 9"; }
#king-attacks .chessboard-21da3 .square-highlight[data-square-coord="e5"]:after { content: "<< 1"; }
#king-attacks .chessboard-21da3 .square-highlight[data-square-coord="c4"]:after { content: ">> 9"; }
#king-attacks .chessboard-21da3 .square-highlight[data-square-coord="d4"]:after { content: ">> 8"; }
#king-attacks .chessboard-21da3 .square-highlight[data-square-coord="e4"]:after { content: ">> 7"; }
#king-attacks .chessboard-21da3 .square-highlight[data-square-coord="c5"]:after { content: ">> 1"; }

#king-attacks-edge-left .chessboard-21da3 .square-highlight:after,
#king-attacks-edge-right .chessboard-21da3 .square-highlight:after { font-size: .65em; white-space: nowrap; }
#king-attacks-edge-left .chessboard-21da3 .square-highlight[data-square-coord="h2"]:after { content: ">>9"; }
#king-attacks-edge-left .chessboard-21da3 .square-highlight[data-square-coord="h3"]:after { content: ">>1"; }
#king-attacks-edge-left .chessboard-21da3 .square-highlight[data-square-coord="h4"]:after { content: "<<7"; }
#king-attacks-edge-right .chessboard-21da3 .square-highlight[data-square-coord="a4"]:after { content: ">>7"; }
#king-attacks-edge-right .chessboard-21da3 .square-highlight[data-square-coord="a5"]:after { content: "<<1"; }
#king-attacks-edge-right .chessboard-21da3 .square-highlight[data-square-coord="a6"]:after { content: "<<9"; }

@media (min-width: 48em) {
  #king-attacks-edge-left .chessboard-21da3 .square-highlight:after,
  #king-attacks-edge-right .chessboard-21da3 .square-highlight:after { font-size: smaller; white-space: nowrap; }
  #king-attacks-edge-left .chessboard-21da3 .square-highlight[data-square-coord="h2"]:after { content: ">> 9"; }
  #king-attacks-edge-left .chessboard-21da3 .square-highlight[data-square-coord="h3"]:after { content: ">> 1"; }
  #king-attacks-edge-left .chessboard-21da3 .square-highlight[data-square-coord="h4"]:after { content: "<< 7"; }
  #king-attacks-edge-right .chessboard-21da3 .square-highlight[data-square-coord="a4"]:after { content: ">> 7"; }
  #king-attacks-edge-right .chessboard-21da3 .square-highlight[data-square-coord="a5"]:after { content: "<< 1"; }
  #king-attacks-edge-right .chessboard-21da3 .square-highlight[data-square-coord="a6"]:after { content: "<< 9"; }
}

#king-attacks .chessboard-21da3 .square-highlight:after,
#king-attacks-edge-left .chessboard-21da3 .square-highlight:after,
#king-attacks-edge-right .chessboard-21da3 .square-highlight:after {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: smaller;
}
</style>

<div id="king-attacks"></div>

By putting this calculation in a loop we can create a bitboard of king attacks for every square.
However, we have to be careful when the king is not in the middle of the board.
Consider what might happen if the king was on the edge:

<div class="chessboard-grid-double">
  <div id="king-attacks-edge-left"></div>
  <div id="king-attacks-edge-right"></div>
</div>

It looks like the king attacks several squares on the other side of the board, but this is of course not true.
We can avoid pieces wrapping around the edges by applying a bit-mask to the king square before shifting it:

```rust
const NOT_FILE_A: u64 = !0x0101_0101_0101_0101;
const NOT_FILE_H: u64 = !0x8080_8080_8080_8080;
```

<div id="file-masks" class="chessboard-grid-double">
  <div style="text-align: center"><code>NOT_FILE_A</code> mask</div>
  <div style="text-align: center"><code>NOT_FILE_H</code> mask</div>
  <div id="not-file-a-mask"></div>
  <div id="not-file-h-mask"></div>
</div>

Now, when applying a shift that moves the king towards the left edge we should first mask it with `NOT_FILE_A`.
Similarly, we mask it with `NOT_FILE_H` when shifting towards the right edge.

Here's how the logic above is modified to use these masks and populate a lookup table:

```rust
let mut KING_ATTACKS = [0; 64];

for square_index in 0..64 {
    let square = 1 << square_index;

    KING_ATTACKS[square_index] =
          square << 8
        | square >> 8

        | (square & NOT_FILE_H) << 1
        | (square & NOT_FILE_A) >> 1

        | (square & NOT_FILE_A) << 7
        | (square & NOT_FILE_H) << 9

        | (square & NOT_FILE_H) >> 7
        | (square & NOT_FILE_A) >> 9;
}
```

Notice that we don't need a mask when shifting by 8 bits.
This is because wrapping around the top or bottom edges of the board doesn't actually occur with this bitboard layout.
Right-shifting the `e1` square by 8 simply means the bit disappears and no wrapping occurs.

We can now trivially write a function for finding king attacks:

```rust
fn get_king_attacks(square: Square) -> u64 {
    KING_ATTACKS[square]
}
```

Pawn and knight attack tables are mostly the same, except with different bitwise shifts and masks.
Check out the source to see [how knight attacks are calculated](https://github.com/tomcant/chess-rs/blob/04aea5c0b9423ffcabb676f35bc72c6970c7111b/src/movegen/attacks.rs#L126), for example.

At the beginning of this section we saw the `get_attacks()` function, which lives at the heart of the move generator.
Here it is again:

```rust
fn get_attacks(piece: Piece, square: Square, board: &Board) -> u64 {
    match piece {
        WP | BP => get_pawn_attacks(...),
        WN | BN => get_knight_attacks(...),
        WB | BB => get_bishop_attacks(...),
        WR | BR => get_rook_attacks(...),
        WQ | BQ => get_bishop_attacks(...) | get_rook_attacks(...),
        WK | BK => get_king_attacks(...),
    }
}
```

With the methods described above we can implement all the "piece attack" functions and this gets us most of the way to generating all the moves in a position.

## Other types of move

There's a few types of move that require a little more than just the attack squares to find:

- pawn advances,
- pawn promotions,
- en-passant captures, and
- castling.

### Pawn advances

Depending on which colour is advancing, the pawn's square index shifts by +/&ndash; 8:

```rust
impl Square {
    fn advance(&self, colour: Colour) -> Self {
        match colour {
            White => Self(self.0 + 8),
            Black => Self(self.0 - 8),
        }
    }
}
```

Expanding on this, given a square and a colour, the following function checks if the square one ahead is empty.
If the square is on the pawn's start rank and the square one ahead is empty, it also checks the square two ahead.
The result is a bitboard with at most two 1-bits.

```rust
fn get_pawn_advances(square: Square, colour: Colour, board: &Board) -> u64 {
    let one_ahead = square.advance(colour);

    if board.has_piece_at(one_ahead) {
        return 0;
    }

    if square.rank() != PAWN_START_RANKS[colour] {
        return one_ahead.u64();
    }

    let two_ahead = one_ahead.advance(colour);

    if board.has_piece_at(two_ahead) {
        return one_ahead.u64();
    }

    one_ahead.u64() | two_ahead.u64()
}
```

Since the function produces a bitboard we can just merge it with the attacks bitboard for the pawn to leverage the behaviour of converting the bitboard to moves later.

```rust
let mut to_squares = get_attacks(piece, from_square, board);

if piece.is_pawn() {
    to_squares |= get_pawn_advances(from_square, colour_to_move, board);
}
```

<div class="chessboard-bitwise-calc">
  <div id="pawn-attacks"></div>
  <div><strong>OR</strong></div>
  <div id="pawn-advances2"></div>
  <div><strong>=</strong></div>
  <div id="pawn-attacks-with-advances"></div>
</div>

### Pawn promotions

If a pawn advance would move the pawn to the 1st or 8th ranks then there are four moves available, one for each promotion piece.
Checking if a square is on the back rank is a simple bitwise AND operation:

```rust
const BACK_RANKS: u64 = 0xFF00_0000_0000_00FF;

impl Square {
    fn is_back_rank(&self) -> bool {
        *self & BACK_RANKS != 0
    }
}
```

Now, when converting a pawn's bitboard of available squares into a list of moves, we can determine whether the four promotion moves should be added:

```rust
for to_square in to_squares {
    // ...

    if piece.is_pawn() && to_square.is_back_rank() {
        moves.push(...);
    }

    // ...
}
```

### En-passant captures

Recall that the `Position` structure has an `en_passant_square` property.
This gets set when applying a double pawn advance and reset when any other move occurs.
En-passant is only possible if the property is set _and_ an opponent pawn attacks that square.
We can see if this is the case by finding the pawn attacks from the perspective of the en-passant square and checking for any overlap with the colour-to-move's pawns:

```rust
fn get_en_passant_attacks(
    en_passant_square: Square,
    colour: Colour,
    board: &Board
) -> u64 {
    get_pawn_attacks(en_passant_square, colour.flip(), board)
        & board.pieces(Piece::pawn(colour))
}
```

We'll see how to convert the result of this function to a list of moves later.

### Castling

The last type of _special_ move is castling.
The colour-to-move is allowed to castle if:

1. the king and rook have not moved from their start squares,
2. the squares between the king and rook are not occupied,
3. the square the king will pass through is not attacked, and
4. the colour-to-move is not in check.

#### 1. The king and rook have not moved from their start squares

The `Position` structure has a `castling_rights` property.
Starting from a value that indicates full rights to castle, this property is updated to reflect which rights are lost as the pieces move:

```rust
impl Position {
    fn do_move(&mut self, mv: &Move) {
        let piece = self.board.piece_at(mv.from);

        if piece.is_king() {
            self.castling_rights
                .remove_for_colour(self.colour_to_move);
        }

        // Maybe a rook left its start square?
        if mv.from.is_corner() {
            self.castling_rights
                .remove_for_square(mv.from);
        }

        // Maybe a rook was captured?
        if mv.to.is_corner() {
            self.castling_rights
                .remove_for_square(mv.to);
        }

        // ...
    }
}
```

#### 2. The squares between the king and rook are not occupied

The squares to check depend on which colour is castling and in which direction:

```rust
const WHITE_KING_SIDE_PATH: u64 = F1 | G1;
const WHITE_QUEEN_SIDE_PATH: u64 = B1 | C1 | D1;

const BLACK_KING_SIDE_PATH: u64 = F8 | G8;
const BLACK_QUEEN_SIDE_PATH: u64 = B8 | C8 | D8;
```

With these constants, we can use familiar bitwise logic to determine if there are pieces on these squares:

```rust
impl Board {
    fn has_occupancy_at(&self, squares: u64) -> bool {
        self.occupancy() & squares != 0
    }
}
```

#### 3. The square the king will pass through is not attacked

The king can't castle _through_ check, so we need to determine if any of the opponent's pieces attack the square next to the king.
For example, black may still have the right to castle in the following position, but it would not be legal because the white bishop on `c5` blocks it:

<div id="cannot-castle-through-check"></div>

In this scenario, if we calculate the attacks for a bishop on `f8`, we would find an overlap with the `c5` square:

<div id="cannot-castle-through-check-bishop-attacks"></div>

This must mean the bishop on `c5` attacks `f8` and black can't castle.
We can use this idea to write a function that takes a square and calculates a bitboard of all its attacking pieces:

```rust
fn get_attackers(square: Square, colour: Colour, board: &Board) -> u64 {
    let bishop_attacks = get_bishop_attacks(...);
    let rook_attacks = get_rook_attacks(...);
    let queen_attacks = bishop_attacks | rook_attacks;

      (board.pieces(Piece::pawn(colour))   & get_pawn_attacks(...))
    | (board.pieces(Piece::knight(colour)) & get_knight_attacks(...))
    | (board.pieces(Piece::bishop(colour)) & bishop_attacks)
    | (board.pieces(Piece::rook(colour))   & rook_attacks)
    | (board.pieces(Piece::queen(colour))  & queen_attacks)
    | (board.pieces(Piece::king(colour))   & get_king_attacks(...))
}
```

Finally, we can use this to check if a square is attacked by a given colour:

```rust
fn is_attacked(square: Square, colour: Colour, board: &Board) -> bool {
    get_attackers(square, colour, board) != 0
}
```

#### 4. The colour-to-move is not in check

This simply reuses the `is_attacked()` function to see if the king square is attacked:

```rust
fn is_in_check(colour: Colour, board: &Board) -> bool {
    let king_square = Square::first(board.pieces(Piece::king(colour)));

    is_attacked(king_square, colour.flip(), board)
}
```

All that's left to do is to put these rules into a function that returns a bitboard of squares the king can move to when castling:

```rust
fn get_castling(rights: CastlingRights, colour: Colour, board: &Board) -> u64 {
    if is_in_check(colour, board) {
        return 0;
    }

    match colour {
        White => get_white_castling(rights, board),
        Black => get_black_castling(rights, board),
    }
}

fn get_white_castling(rights: CastlingRights, board: &Board) -> u64 {
    let mut white_castling = 0;

    if rights.has(WhiteKing)
        && !board.has_occupancy_at(WHITE_KING_SIDE_PATH)
        && !is_attacked(F1, Black, board)
    {
        white_castling |= G1;
    }

    if rights.has(WhiteQueen)
        && !board.has_occupancy_at(WHITE_QUEEN_SIDE_PATH)
        && !is_attacked(D1, Black, board)
    {
        white_castling |= C1;
    }

    white_castling
}

fn get_black_castling(rights: CastlingRights, board: &Board) -> u64 {
    // ...
}
```

Similarly to pawn advances, the resultant bitboard for castling moves can be merged with the attack squares for the king:

```rust
let mut to_squares = get_attacks(piece, from_square, board);

if piece.is_king() {
    to_squares |= get_castling(pos.castling_rights, colour_to_move, board);
}
```

<div class="chessboard-bitwise-calc">
  <div id="king-attacks-2"></div>
  <div><strong>OR</strong></div>
  <div id="king-castling"></div>
  <div><strong>=</strong></div>
  <div id="king-attacks-with-castling"></div>
</div>

## Converting Bitboards to Moves

By this point we can generate a bitboard containing all the available squares for any piece on the board.
Now we just need to convert these bitboards into a list of moves and we're done!

Suppose we have the following bitboard for the bishop's available moves:

<div id="bitboard-iteration-1"></div>

A specialised `Square` constructor allows me to get the first square in the bitboard and unset its corresponding bit:

```rust
impl Square {
    fn next(squares: &mut u64) -> Self {
        let square = Self::first(*squares);
        *squares ^= square;
        square
    }
}
```

I wouldn't usually be a fan of such an impurity*, but I've found this to be extremely useful for iterating over all the 1-bits in a loop:

```rust
let mut moves = vec![];
let mut to_squares = ...;

while to_squares != 0 {
    let to_square = Square::next(&mut to_squares);
    moves.push(Move::new(from_square, to_square));
}
```

Of course, this isn't only used to convert bitboards to moves.
This technique can be used wherever there's a need to iterate over a bitboard, as we'll see below...

<small>* Perhaps the only saving grace is that at least Rust makes clear what's going on with its `&mut` notation.</small>

## Putting Everything Together

For completeness, here's the whole move generation function:

```rust
fn generate_moves(pos: &Position) -> Vec<Move> {
    let mut moves = vec![];
    let board = pos.board;
    let colour = pos.colour_to_move;

    for piece in Piece::pieces_by_colour(colour) {
        let mut pieces = board.pieces(piece);

        while pieces != 0 {
            let from_square = Square::next(&mut pieces);

            let mut to_squares = !board.pieces_by_colour(colour)
                & get_attacks(piece, from_square, board);

            if piece.is_pawn() {
                to_squares |= get_pawn_advances(from_square, colour, board);
            } else if piece.is_king() {
                to_squares |= get_castling(pos.castling_rights, colour, board);
            }

            while to_squares != 0 {
                let to_square = Square::next(&mut to_squares);

                if piece.is_pawn() && to_square.is_back_rank() {
                    for piece in Piece::promotions(colour) {
                        moves.push(
                            Move::promotion(from_square, to_square, piece)
                        );
                    }

                    continue;
                }

                moves.push(Move::new(from_square, to_square));
            }
        }
    }

    if let Some(en_passant_square) = pos.en_passant_square {
        let mut from_squares =
            get_en_passant_attacks(en_passant_square, colour, board);

        while from_squares != 0 {
            let from_square = Square::next(&mut from_squares);
            moves.push(Move::new(from_square, en_passant_square));
        }
    }

    moves
}
```

## Verifying Correctness

Writing a move generator has been one of the most error-prone tasks I've worked on.
With so many nuances to the rules it can be tricky to implement a completely bug-free program, so having a reliable test suite is crucial.

Besides having a suite of TDD-style unit tests still hanging around from the early phases of development, my general approach to testing has been to rely on [perft](https://www.chessprogramming.org/Perft), a method used to give an indication of correctness for chess move generators.

The basic idea is to compare the number of generated moves with the known correct value for a given position.
For example, there are 20 moves in the start position for white, and for each of those there are 20 replies for a total of 400 moves after 2 turns.
The following table shows the number of possible moves as the number of turns increases:

| Depth | Move count  |
| :---: | :-----------|
| 1     | 20          |
| 2     | 400         |
| 3     | 8,902       |
| 4     | 197,281     |
| 5     | 4,865,609   |
| 6     | 119,060,324 |

I wanted to be able to write a test like this:

```rust
#[test]
fn perft_start_position() {
    assert_eq!(perft(Position::startpos(), 6), 119_060_324);
}
```

To support this we need a function that counts moves in a position recursively:

```rust
fn perft(pos: &mut Position, depth: u8) -> u32 {
    if depth == 0 {
        return 1;
    }

    let mut count = 0;

    for mv in generate_moves(pos) {
        pos.do_move(mv);

        if pos.is_legal() {
            count += perft(pos, depth - 1);
        }

        pos.undo_move(mv);
    }

    count
}
```

Note that I'm checking the position is legal after applying each move because the engine only generates _pseudo-legal_ moves, meaning that a move could leave the player in check, which would not be legal.

It was extremely useful to have tests like this during development.
They helped me find so many unusual bugs that I never would have noticed otherwise.
For example, here's a position that highlights a common gotcha:

<div id="perft-position-3"></div>

In this position, if black plays a double pawn advance on the c-file then technically en-passant is available, and at a glance it looks like white's b-pawn could capture en-passant and move to `c6`.
However, this would leave the white king in check by the rook on `h5`, making the move illegal.

I currently verify this position to depth 7:

```rust
#[test]
fn perft_position_3() {
    assert_perft_for_fen(
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        7,
        178_633_661
    );
}
```

Another position I found useful was this one:

<div id="perft-position-4"></div>

White is in check so the number of possible moves should be limited, and after white's turn black has 8 ways to promote the pawn on `b2`.
Black has castling rights on both sides of the board but can only castle queen-side because of white's knight and bishop blocking the king-side path.
This position is great for testing lots of the subtle details in the rules.

I currently verify this position to depth 6:

```rust
#[test]
fn perft_position_4() {
    assert_perft_for_fen(
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        6,
        706_045_033,
    );
}
```

More positions and their move counts are available [on the Chess Programming Wiki](https://www.chessprogramming.org/Perft_Results).

I combine these positions with several others to gain a level of confidence I don't think would be achievable with other forms of testing.
The only drawback is that they're slow, [so I only run these on CI](https://github.com/tomcant/chess-rs/blob/ecd1b077f6211a98f144dad28f510b0748ab8446/.github/workflows/ci.yml#L39).
For development, I run a reduced suite of perft tests that verify lower depths in order to keep the feedback loop fast.

## Performance Considerations

Once I've got the engine working in its entirety I'll revisit some of these areas to work on performance.
Here's a few ideas I have in mind:

- The method I chose for sliding piece attacks involves a lot of repetitive work to find the available squares based on the blocking pieces.
  We can pre-calculate all of this so that the available squares are looked up based on the location of the piece and its blockers.
  The current most efficient method is [Magic bitboards](https://www.chessprogramming.org/Magic_Bitboards).

- Keep track of [pinned pieces](https://en.wikipedia.org/wiki/Pin_(chess)) and always generate legal moves (rather than pseudo-legal).
  This would reduce the number of calls to `is_in_check()`.

- Generate all pawn advances simultaneously instead of on a per-pawn basis:
  ```rust
  let pawn_advances = (pawns << 8) & !board.occupancy();
  ```
  We could use a similar idea for other pieces and this could have a dramatic effect on performance.

It will be interesting to benchmark before and after these changes.
However, bear in mind that the biggest performance gains come from improving positional evaluation so that the engine can cut off large branches of the search tree, since this avoids having to generate moves for so many positions in the first place.

## Onwards: Evaluation

In the next post I'll write about how the engine assigns each chess position a score, the fundamental metric used to find the best move.

♟️

<link rel="stylesheet" href="https://unpkg.com/@chrisoakman/chessboard2@0.4.0/dist/chessboard2.min.css" integrity="sha384-MZONbGYADvdl4hLalNF4d+E/6BVdYIty2eSgtkCbjG7iQJAe35a7ujTk1roZIdJ+" crossorigin="anonymous">
<script src="https://unpkg.com/@chrisoakman/chessboard2@0.4.0/dist/chessboard2.min.js" integrity="sha384-zl6zz0W4cEX3M2j9+bQ2hv9af6SF5pTFrnm/blYYjBmqSS3tdJChVrY9nenhLyNg" crossorigin="anonymous"></script>

<style>
.board-container-41a68 { border-color: #b58863; }

.chessboard-21da3 { width: 50%; margin: 2em auto; }
.chessboard-21da3 img { margin: 0; z-index: 1; }

.chessboard-21da3 .square-highlight,
.chessboard-21da3 .square-fade { position: relative; }

.chessboard-21da3 .square-highlight:after,
.chessboard-21da3 .square-fade:after {
  content: "";
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: #2f363d;
  color: #f0d9b5;
  opacity: 0.85;
}
.chessboard-21da3 .square-fade:after {
  background-color: #fff;
  color: #2f363d;
  opacity: 0.5;
}

.chessboard-21da3 .zero-bit:after { content: "0"; }
.chessboard-21da3 .one-bit:after { content: "1"; }

.chessboard-21da3 .zero-bit:after,
.chessboard-21da3 .one-bit:after {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: smaller;
}

@media (min-width: 48em) {
  .chessboard-21da3 .zero-bit:after { font-size: inherit; }
  .chessboard-21da3 .one-bit:after { font-size: inherit; }
}

.chessboard-grid-double {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1em;
  align-items: center;
  margin: 1em 0;
}
.chessboard-grid-double .chessboard-21da3 {
  width: auto;
  margin: 0;
}

.chessboard-grid-quadruple {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr 1fr;
  gap: .5em;
  align-items: center;
  margin: 1em 0;
}
@media (min-width: 48em) {
  .chessboard-grid-quadruple { gap: 1em; }
}
.chessboard-grid-quadruple .chessboard-21da3 {
  width: auto;
  margin: 0;
  font-size: smaller;
}

.chessboard-bitwise-calc {
  display: grid;
  grid-template-columns: 1fr auto 1fr auto 1fr;
  gap: 0.5em;
  align-items: center;
  margin: 2em 0;
}
.chessboard-bitwise-calc > div {
  text-align: center;
}
.chessboard-bitwise-calc .chessboard-21da3 {
  width: auto;
  margin: 0;
}
</style>

<script>
function addClassToSquares(boardId, squares, cssClass) {
  for (var i = 0; i < squares.length; ++i) {
    document
      .querySelector('#' + boardId + ' [data-square-coord="' + squares[i] + '"]')
      .classList.add(cssClass);
  }
}

function highlightSquares(boardId, squares) {
  addClassToSquares(boardId, squares, 'square-highlight');
}

function fadeSquares(boardId, squares) {
  addClassToSquares(boardId, squares, 'square-fade');
}

function oneBits(boardId, squares) {
  addClassToSquares(boardId, squares, 'one-bit');
  highlightSquares(boardId, squares);
}

function zeroBits(boardId, squares) {
  addClassToSquares(boardId, squares, 'zero-bit');
  fadeSquares(boardId, squares);
}

Chessboard2('bishop-attack-rays', { position: { c3: 'wB' } });
highlightSquares('bishop-attack-rays', ['b4', 'a5', 'e5', 'f6', 'g7', 'h8', 'd4', 'b2', 'a1', 'd2', 'e1']);

Chessboard2('bishop-with-blockers', '7r/pppppp1p/5np1/8/8/2B5/8/8');

Chessboard2('bishop-attack-ray');
Chessboard2('occupancy');
Chessboard2('bishop-attack-blockers');
highlightSquares('bishop-attack-ray', ['d4', 'e5', 'f6', 'g7', 'h8']);
highlightSquares('occupancy', ['c3', 'a7', 'b7', 'c7', 'd7', 'e7', 'f6', 'f7', 'g6', 'h7', 'h8']);
highlightSquares('bishop-attack-blockers', ['f6', 'h8']);

Chessboard2('bishop-attack-ray2');
Chessboard2('occupancy2');
Chessboard2('bishop-attack-blockers2');
highlightSquares('bishop-attack-ray2', ['d4', 'e5', 'f6', 'g7', 'h8']);
highlightSquares('occupancy2', ['g7', 'h8']);
highlightSquares('bishop-attack-blockers2', ['d4', 'e5', 'f6']);

Chessboard2('bishop-attack-ray-blocker-nw', { position: { f3: 'bB' } });
oneBits('bishop-attack-ray-blocker-nw', ['c6', 'a8']);
zeroBits('bishop-attack-ray-blocker-nw', [
  'a6', 'b6',
  'a5', 'b5', 'c5', 'd5', 'e5', 'f5', 'g5', 'h5',
  'a4', 'b4', 'c4', 'd4', 'e4', 'f4', 'g4', 'h4',
  'a3', 'b3', 'c3', 'd3', 'e3', 'f3', 'g3', 'h3',
  'a2', 'b2', 'c2', 'd2', 'e2', 'f2', 'g2', 'h2',
  'a1', 'b1', 'c1', 'd1', 'e1', 'f1', 'g1', 'h1'
]);
fadeSquares('bishop-attack-ray-blocker-nw', [
        'b8', 'c8', 'd8', 'e8', 'f8', 'g8', 'h8',
  'a7', 'b7', 'c7', 'd7', 'e7', 'f7', 'g7', 'h7',
                    'd6', 'e6', 'f6', 'g6', 'h6'
]);

Chessboard2('bishop-attack-ray-blocker-ne', { position: { c3: 'bB' } });
oneBits('bishop-attack-ray-blocker-ne', ['f6', 'h8']);
zeroBits('bishop-attack-ray-blocker-ne', [
  'a6', 'b6', 'c6', 'd6', 'e6',
  'a5', 'b5', 'c5', 'd5', 'e5', 'f5', 'g5', 'h5',
  'a4', 'b4', 'c4', 'd4', 'e4', 'f4', 'g4', 'h4',
  'a3', 'b3', 'c3', 'd3', 'e3', 'f3', 'g3', 'h3',
  'a2', 'b2', 'c2', 'd2', 'e2', 'f2', 'g2', 'h2',
  'a1', 'b1', 'c1', 'd1', 'e1', 'f1', 'g1', 'h1'
]);
fadeSquares('bishop-attack-ray-blocker-ne', [
  'a8', 'b8', 'c8', 'd8', 'e8', 'f8', 'g8',
  'a7', 'b7', 'c7', 'd7', 'e7', 'f7', 'g7', 'h7',
                                      'g6', 'h6'
]);

Chessboard2('bishop-attack-ray-blocker-sw', { position: { f6: 'bB' } });
oneBits('bishop-attack-ray-blocker-sw', ['c3', 'a1']);
zeroBits('bishop-attack-ray-blocker-sw', [
  'a8', 'b8', 'c8', 'd8', 'e8', 'f8', 'g8', 'h8',
  'a7', 'b7', 'c7', 'd7', 'e7', 'f7', 'g7', 'h7',
  'a6', 'b6', 'c6', 'd6', 'e6', 'f6', 'g6', 'h6',
  'a5', 'b5', 'c5', 'd5', 'e5', 'f5', 'g5', 'h5',
  'a4', 'b4', 'c4', 'd4', 'e4', 'f4', 'g4', 'h4',
                    'd3', 'e3', 'f3', 'g3', 'h3'
]);
fadeSquares('bishop-attack-ray-blocker-sw', [
  'a3', 'b3',
  'a2', 'b2', 'c2', 'd2', 'e2', 'f2', 'g2', 'h2',
        'b1', 'c1', 'd1', 'e1', 'f1', 'g1', 'h1'
]);

Chessboard2('bishop-attack-ray-blocker-se', { position: { c6: 'bB' } });
oneBits('bishop-attack-ray-blocker-se', ['f3', 'h1']);
zeroBits('bishop-attack-ray-blocker-se', [
  'a8', 'b8', 'c8', 'd8', 'e8', 'f8', 'g8', 'h8',
  'a7', 'b7', 'c7', 'd7', 'e7', 'f7', 'g7', 'h7',
  'a6', 'b6', 'c6', 'd6', 'e6', 'f6', 'g6', 'h6',
  'a5', 'b5', 'c5', 'd5', 'e5', 'f5', 'g5', 'h5',
  'a4', 'b4', 'c4', 'd4', 'e4', 'f4', 'g4', 'h4',
  'a3', 'b3', 'c3', 'd3', 'e3'
]);
fadeSquares('bishop-attack-ray-blocker-se', [
                                      'g3', 'h3',
  'a2', 'b2', 'c2', 'd2', 'e2', 'f2', 'g2', 'h2',
  'a1', 'b1', 'c1', 'd1', 'e1', 'f1', 'g1'
]);

Chessboard2('king-attacks', { position: { d5: 'wK' } });
highlightSquares('king-attacks', ['c4', 'd4', 'e4', 'c5', 'e5', 'c6', 'd6', 'e6']);

Chessboard2('king-attacks-edge-left', { position: { a4: 'wK' } });
Chessboard2('king-attacks-edge-right', { position: { h4: 'wK' } });
highlightSquares('king-attacks-edge-left', ['a5', 'b5', 'b4', 'b3', 'a3', 'h2', 'h3', 'h4']);
highlightSquares('king-attacks-edge-right', ['h5', 'g5', 'g4', 'g3', 'h3', 'a4', 'a5', 'a6']);

Chessboard2('not-file-a-mask');
zeroBits('not-file-a-mask', ['a8', 'a7', 'a6', 'a5', 'a4', 'a3', 'a2', 'a1']);
oneBits('not-file-a-mask', [
  'b8', 'c8', 'd8', 'e8', 'f8', 'g8', 'h8',
  'b7', 'c7', 'd7', 'e7', 'f7', 'g7', 'h7',
  'b6', 'c6', 'd6', 'e6', 'f6', 'g6', 'h6',
  'b5', 'c5', 'd5', 'e5', 'f5', 'g5', 'h5',
  'b4', 'c4', 'd4', 'e4', 'f4', 'g4', 'h4',
  'b3', 'c3', 'd3', 'e3', 'f3', 'g3', 'h3',
  'b2', 'c2', 'd2', 'e2', 'f2', 'g2', 'h2',
  'b1', 'c1', 'd1', 'e1', 'f1', 'g1', 'h1',
]);

Chessboard2('not-file-h-mask');
zeroBits('not-file-h-mask', ['h8', 'h7', 'h6', 'h5', 'h4', 'h3', 'h2', 'h1']);
oneBits('not-file-h-mask', [
  'a8', 'b8', 'c8', 'd8', 'e8', 'f8', 'g8',
  'a7', 'b7', 'c7', 'd7', 'e7', 'f7', 'g7',
  'a6', 'b6', 'c6', 'd6', 'e6', 'f6', 'g6',
  'a5', 'b5', 'c5', 'd5', 'e5', 'f5', 'g5',
  'a4', 'b4', 'c4', 'd4', 'e4', 'f4', 'g4',
  'a3', 'b3', 'c3', 'd3', 'e3', 'f3', 'g3',
  'a2', 'b2', 'c2', 'd2', 'e2', 'f2', 'g2',
  'a1', 'b1', 'c1', 'd1', 'e1', 'f1', 'g1'
]);

Chessboard2('pawn-attacks', { position: { d2: 'wP' } });
Chessboard2('pawn-advances2', { position: { d2: 'wP' } });
Chessboard2('pawn-attacks-with-advances', { position: { d2: 'wP' } });
highlightSquares('pawn-attacks', ['c3', 'e3']);
highlightSquares('pawn-advances2', ['d3', 'd4']);
highlightSquares('pawn-attacks-with-advances', ['c3', 'e3', 'd3', 'd4']);

Chessboard2('cannot-castle-through-check', { position: { h8: 'bR', c5: 'wB', e8: 'bK' } });

Chessboard2('cannot-castle-through-check-bishop-attacks', { position: { h8: 'bR', c5: 'wB', f8: 'wB', e8: 'bK' } });
highlightSquares('cannot-castle-through-check-bishop-attacks', ['e7', 'd6', 'c5', 'b4', 'a3', 'g7', 'h6']);

Chessboard2('king-attacks-2', { position: { a1: 'wR', e1: 'wK', h1: 'wR' } });
Chessboard2('king-castling', { position: { a1: 'wR', e1: 'wK', h1: 'wR' } });
Chessboard2('king-attacks-with-castling', { position: { a1: 'wR', e1: 'wK', h1: 'wR' } });
highlightSquares('king-attacks-2', ['d1', 'd2', 'e2', 'f2', 'f1']);
highlightSquares('king-castling', ['c1', 'g1']);
highlightSquares('king-attacks-with-castling', ['d1', 'd2', 'e2', 'f2', 'f1', 'c1', 'g1']);

Chessboard2('bitboard-iteration-1', { position: { c3: 'wB' }});
oneBits('bitboard-iteration-1', ['d4', 'e5', 'f6', 'g7', 'h8']);

Chessboard2('perft-position-3', { position: '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1' });
Chessboard2('perft-position-4', { position: 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1' });
</script>
