---
title: Building a Chess AI, Part 3 – Evaluation
summary: This is the third post in a series I've been writing about building a chess engine. The last post was about [move generation](/posts/2023/05/building-a-chess-ai-part-2-move-generation/), and in this post I'm going to write about how the engine decides who's winning.
date: 2023-06-18
---

- [Part 1 – Game State](/posts/2023/03/building-a-chess-ai-part-1-game-state/)
- [Part 2 – Move Generation](/posts/2023/05/building-a-chess-ai-part-2-move-generation/)
- **Part 3 – Evaluation**
- Part 4 – Search, coming soon...

This is the third post in a series I've been writing about building a chess engine.
The last post was about [move generation](/posts/2023/05/building-a-chess-ai-part-2-move-generation/), and in this post I'm going to write about how the engine decides who's winning.

If you're interested in seeing the full code, check out [tomcant/chess-rs](https://github.com/tomcant/chess-rs) on GitHub.

Hypothetically speaking, with an enormous amount of computing power the fate of any chess position could be determined by simulating every combination of moves until the end of the game.
We would know for any position whether the colour-to-move can force a win, should offer a draw, or should simply resign.

In reality, however, with [the number of possible chess positions](https://en.wikipedia.org/wiki/Shannon_number) surpassing the number of atoms in the observable universe, we wouldn't even be able to store the unfathomably large game tree.
Instead, engines estimate winning chances based on a number of heuristics:

- material balance,
- piece activity,
- pawn structure,
- king safety,
- central control,
- piece coordination

... to name a few.

The goal of evaluation is to assign each position a score that indicates the colour-to-move's winning chances.
By simulating a number of turns into the future and scoring all the positions we could arrive at, the engine can pick the move that most likely leads to a better position.

In the first post I wrote about one of the goals of the engine: _to play sensible chess_.
What I've found is that very few of these heuristics are actually required to start seeing some sensible moves.
I started with the first two above, material balance and piece activity.

## Material Balance

The most obvious indicator of a winning position is when one colour has more pieces than the other, so this seems like a good place to start.
If we assign relative values to each piece then the sum of the white pieces minus the sum of the black pieces is the material balance.

These weightings vary from engine to engine, but it's typical to see something like this:

| Pawn | Knight | Bishop | Rook | Queen |
| :--: | :----: | :----: | :--: | :---: |
| 1    | 3      | 3.5    | 5    | 9     |

Some engines value knights and bishops equally, but I decided to value bishops slightly higher because having both of them on the board is often a positional advantage.
The value of the king is not considered because a position without them would not be legal.

A simple implementation is as follows:

```rust
const PIECE_WEIGHTS: [i32; 12] = [
    100, 300, 350, 500, 900, 0, // WP to WK
    100, 300, 350, 500, 900, 0, // BP to BK
];

fn material_sum(colour: Colour, board: &Board) -> i32 {
    Piece::pieces_by_colour(colour)
        .fold(0, |sum, piece| {
            sum + PIECE_WEIGHTS[piece] * board.count_pieces(piece)
        })
}
```

Notice that the weight of each piece is multiplied by 100.
This is to ensure that material balance is the dominant heuristic and prevents the engine from mistakenly thinking that a better score for another heuristic is worth losing material for.

## Piece Activity

Piece activity is important because it directly impacts a piece's ability to influence the game.
It's obvious from the following position that the activity of white's pieces is an advantage even though the material balance is even:

<div id="piece-activity-board"></div>

With white to move, Stockfish 15 gives this position a score of almost +9.
In terms of material balance that's the equivalent of playing with an extra queen!

Using a technique known as [piece-square tables](https://www.chessprogramming.org/Piece-Square_Tables) we can encourage the engine to put pieces on more active squares.
The idea is to assign values to squares to indicate the desirability of putting particular pieces there.

Below are the piece-square tables I'm currently using for pawns.

<div class="chessboard-grid-double">
  <div style="text-align: center"><em>White pawns</em></div>
  <div style="text-align: center"><em>Black pawns</em></div>
  <div id="white-pawn-psqt" class="piece-square-table"></div>
  <div id="black-pawn-psqt" class="piece-square-table"></div>
</div>

These values reward moving pawns to positions where they are more likely to promote.
Notice the d- and e-files start with negative values so that the engine is more inclined to move these pawns first.
This is useful at the start of the game when it's important to gain control of the centre.
These tables are in fact mirror images of each other, because what's good for the white pawns would be equally good for black, only on the other side of the board.

Similarly, below are the tables I'm currently using for the kings.

<div class="chessboard-grid-double">
  <div style="text-align: center"><em>White king</em></div>
  <div style="text-align: center"><em>Black king</em></div>
  <div id="white-king-psqt" class="piece-square-table"></div>
  <div id="black-king-psqt" class="piece-square-table"></div>
</div>

Here we can see the engine will favour positions with a castled king and will be discouraged from stepping forward at the start of the game.
The central squares are given higher values because the king should avoid the edges of the board where the threat of checkmate is usually higher.

The [tables for other pieces](https://github.com/tomcant/chess-rs/blob/main/src/eval/psqt.rs#L34) work in similar ways: knights are more effective when they can reach the centre; bishops prefer the long diagonals; a white rook is usually more of a threat on the 7th rank; etc.

Using these tables, here's how the engine calculates overall piece activity for a colour:

```rust
fn piece_activity(colour: Colour, board: &Board) -> i32 {
    Piece::pieces_by_colour(colour)
        .fold(0, |mut activity, piece| {
            let mut pieces = board.pieces(piece);

            while pieces != 0 {
                let square = Square::next(&mut pieces);
                activity += PSQT[piece][square];
            }

            activity
        })
}
```

After material balance, piece-square tables give the best returns for the effort required, so it makes sense to implement these next.

Although I've kept my implementation simple, it's common to see engines use different tables depending on the phase of the game.
This allows for fine-tuning based on various criteria like number of pieces remaining, available space, etc.
The difficulty is in determining when each phase of the game starts and ends.
I've left this for something to explore once the rest of the engine is working correctly.

## The Evaluation Function

With the logic for these heuristics now available, we can write a function that calculates a score given a position.

Since chess is a [zero-sum game](https://en.wikipedia.org/wiki/Zero-sum_game), what's good for one player is equally bad for the other.
This means we only need to evaluate the position from the perspective of one colour, say white, and simply negate it if the colour-to-move is black.

```rust
fn eval(pos: &Position) -> i32 {
    let board = &pos.board;

    let eval =
          material_sum(White, board) - material_sum(Black, board)
        + piece_activity(White, board) - piece_activity(Black, board);

    match pos.colour_to_move {
        White => eval,
        Black => -eval,
    }
}
```

In my implementation, the evaluation function doesn't need to consider checkmate or stalemate.
As we'll see in the next post, these terminal states are handled during search and the evaluation function won't even be called in such positions.

## In Search of the Best Move

The evaluation function assigns a score to a position based solely on the information in the position alone.
On its own, the function doesn't see what might happen in a few moves time, or even on the very next move; it simply evaluates the position it sees during a single frame of the game.
If the colour-to-move has more material and better piece activity but is about to be checkmated, the function will be none the wiser.
It's often referred to as _static_ evaluation for this reason.

To use the evaluation function in a meaningful way we need to search through the positions the game could arrive at, using the score to guide us along the best path.
In the next post I'll write about how the search works using various techniques such as iterative deepening, alpha-beta pruning, quiescence search and move ordering.

♟️

<link rel="stylesheet" href="https://unpkg.com/@chrisoakman/chessboard2@0.4.0/dist/chessboard2.min.css" integrity="sha384-MZONbGYADvdl4hLalNF4d+E/6BVdYIty2eSgtkCbjG7iQJAe35a7ujTk1roZIdJ+" crossorigin="anonymous">
<script src="https://unpkg.com/@chrisoakman/chessboard2@0.4.0/dist/chessboard2.min.js" integrity="sha384-zl6zz0W4cEX3M2j9+bQ2hv9af6SF5pTFrnm/blYYjBmqSS3tdJChVrY9nenhLyNg" crossorigin="anonymous"></script>

<style>
.board-container-41a68 { border-color: #b58863; }

.chessboard-21da3 { width: 50%; margin: 2em auto; }
.chessboard-21da3 img { margin: 0; }

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

.piece-square-table .chessboard-21da3 [data-square-coord] {
  position: relative;
}
.piece-square-table .chessboard-21da3 [data-square-coord]:after {
  content: "";
  display: flex;
  align-items: center;
  justify-content: center;
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(255, 255, 255, 0.5);
  color: #2f363d;
  font-size: x-small;
  font-weight: bold;
  white-space: nowrap;
}
@media (min-width: 48em) {
  .piece-square-table .chessboard-21da3 [data-square-coord]:after {
    font-size: smaller;
  }
}
</style>

<script>
var pieceSquareTableMap = [
  'a8', 'b8', 'c8', 'd8', 'e8', 'f8', 'g8', 'h8',
  'a7', 'b7', 'c7', 'd7', 'e7', 'f7', 'g7', 'h7',
  'a6', 'b6', 'c6', 'd6', 'e6', 'f6', 'g6', 'h6',
  'a5', 'b5', 'c5', 'd5', 'e5', 'f5', 'g5', 'h5',
  'a4', 'b4', 'c4', 'd4', 'e4', 'f4', 'g4', 'h4',
  'a3', 'b3', 'c3', 'd3', 'e3', 'f3', 'g3', 'h3',
  'a2', 'b2', 'c2', 'd2', 'e2', 'f2', 'g2', 'h2',
  'a1', 'b1', 'c1', 'd1', 'e1', 'f1', 'g1', 'h1'
];
function pieceSquareTable(boardId, table) {
  var css = '';

  for (var i = 0; i < table.length; ++i) {
    if (table[i] === 0) continue;
    css += '#' + boardId + ' [data-square-coord="' + pieceSquareTableMap[i] + '"]:after { content: "' + table[i] + '"; }';
  }

  document.head.appendChild(document.createElement('style')).innerHTML = css;
}

Chessboard2('piece-activity-board', { position: 'rnbqkbnr/pppppppp/8/8/2PP1B2/1PNBPN1P/P1Q2PP1/2RR2K1 w kq - 0 1' });

Chessboard2('white-pawn-psqt');
pieceSquareTable('white-pawn-psqt', [
   0,   0,   0,   0,   0,   0,   0,   0,
  60,  60,  60,  60,  60,  60,  60,  60,
  40,  40,  40,  50,  50,  40,  40,  40,
  20,  20,  20,  40,  40,  20,  20,  20,
   5,   5,  15,  30,  30,  10,   5,   5,
   5,   5,  10,  20,  20,   5,   5,   5,
   5,   5,   5, -30, -30,   5,   5,   5,
   0,   0,   0,   0,   0,   0,   0,   0
]);

Chessboard2('black-pawn-psqt');
pieceSquareTable('black-pawn-psqt', [
   0,   0,   0,   0,   0,   0,   0,   0,
   5,   5,   5, -30, -30,   5,   5,   5,
   5,   5,  10,  20,  20,   5,   5,   5,
   5,   5,  15,  30,  30,  10,   5,   5,
  20,  20,  20,  40,  40,  20,  20,  20,
  40,  40,  40,  50,  50,  40,  40,  40,
  60,  60,  60,  60,  60,  60,  60,  60,
   0,   0,   0,   0,   0,   0,   0,   0
]);

Chessboard2('white-king-psqt');
pieceSquareTable('white-king-psqt', [
  0,   0,   0,   0,   0,   0,   0,   0,
  0,   0,   0,   0,   0,   0,   0,   0,
  0,   0,   0,   0,   0,   0,   0,   0,
  0,   0,   0,  20,  20,   0,   0,   0,
  0,   0,   0,  20,  20,   0,   0,   0,
  0,   0,   0,   0,   0,   0,   0,   0,
  0,   0,   0, -10, -10,   0,   0,   0,
  0,   0,  20, -10, -10,   0,  20,   0
]);

Chessboard2('black-king-psqt');
pieceSquareTable('black-king-psqt', [
  0,   0,  20, -10, -10,   0,  20,   0,
  0,   0,   0, -10, -10,   0,   0,   0,
  0,   0,   0,   0,   0,   0,   0,   0,
  0,   0,   0,  20,  20,   0,   0,   0,
  0,   0,   0,  20,  20,   0,   0,   0,
  0,   0,   0,   0,   0,   0,   0,   0,
  0,   0,   0,   0,   0,   0,   0,   0,
  0,   0,   0,   0,   0,   0,   0,   0,
]);
</script>
