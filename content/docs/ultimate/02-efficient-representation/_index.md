---
title: Efficient Representation
---

# Efficient Representation of Ultimate Tic Tac Toe

Any efficient search engine over a game tree requires an efficient implementation of the game at the core. On this page I'll talk about my Ultimate Tic Tac Toe implementation and the choices I've made.

The core decision for any game implementation is the representation of the board. The representation determines or constrains how efficient any operations on the board can be implemented.

## Mutability

Game engines, be they minimax AIs or solvers, tend to have to generate large numbers of positions during their search, including exploring numerous children of a position. To support this mode of operation, there are generally two high-level design choices available to an implementer:

Mutable boards and `undo()`
: We can have our `make_move()` method mutate a board representation in place, and provide some form of `undo()` method to "un-make" moves and return to the previous position. This lets us search a node's children by repeatedly making a move, considering that position, and then calling `undo()` to return to the previous position.

Immutable boards
: We can, instead, have `make_move()` create and return an entirely new board instance, leaving the original board unchanged. Exploring a node's children then is a simple matter of calling `make_move()` separately for each move we want to consider.


Mutable boards can be more efficient, due to not having to copy the board state on every move, but instead only updating the subset of the state that was implicated by a single move. However, they also tend to be more error-prone both to implement and use, for all the usual reasons that mutability can be fraught. They also add complexity when parallelizing a search, since positions that will be shared between threads must be copied anyways.

For game engines I've implemented, including Ultimate Tic Tac Toe, I have tended to opt for immutable positions, and using careful representations to make copying efficient. In particular, for my Ultimate Tic Tac Toe engine, positions are represented in 40 bytes and can be copied by directly copying the underlying bytes, which is an almost free operation on modern CPUs, especially compared to actually operating on that board.


## Bitboards

My Ultimate Tic Tac Toe engine uses [bitboards][bitboards], a family of board representations borrowed largely from the field of computer chess. I have previously implemented a bitboard-based engine for my [Taktician][taktician-bits] Tak AI.

Bitboards represent a board using a set of bitmasks, which each devote a single bit to each square of the board, representing some property of that square.

Bitboards have at least two significant advantages:
- They are very compact. As mentioned above, it is important that copying boards be very efficient, and making boards small enough to fit into a few machine registers accomplishes this goal nicely.
- They let us use bitwise and arithmetic operations to operate on boards. The field of chess AI is full of clever optimizations to use bitwise operations to compute queries like "What are all squares White's rooks can move to?" using a small handful of machine instructions.

# Our representation

At core, an Ultimate Tic Tac Toe engine needs to track the state of each of the 81 underlying squares of the [local boards][local], and each of the 9 squares of the global boards. The local squares each have three possible states: empty, `X`, and `O`, and the global squares have the additional possibility of "Drawn".

I chose to represent these using a set of bitmasks. The three or four possibilities can be represented using two bits, one representing `X` and one representing `O`; for the global boards, setting both bits corresponds to a draw.

This means we need 18 bits per board, which is a slightly frustrating number on CPU architectures optimized around small powers of 2, being awkwardly larger than `16`, and frustratingly smaller than `32`. However, I noted that `3*9` is reasonably close to `32`, suggesting that we use a 32-bit word to represent an entire global row's worth of bits.

I therefore settled on using a single `u32` to represent the global board, arranged as a pair of 9-bit bitmasks aligned to 16-byte chunks for efficient access:

```rust
struct GlobalStates {
    x: u16,
    o: u16,
}
```

And packed each row of the global board into a pair of `u23` values, one each for `x` and `o`:

```rust
struct GlobalRow {
  // These are each a packed [u9; 3]
  x: u32,
  o: u32,
}
struct LocalBoards([GlobalRow; 3]);
```

This comes to `7*4 = 28` bytes; the rest of the board space is consumed by metadata, including an 8-byte hash value I'll talk about in a later section.

## Efficient bitwise operations

Storing positions as bitmasks admits some useful efficient operations. For a start, `x | o` gives us all occupied squares, and negating that bitmask gives us all empty squares, which is useful for move generation and computing various heuristics.

In additiona, because a single board can be represented as 18 bits, it's feasible to build lookup tables keyed by an entire board, letting us embed expensive computations into a single lookup; a single lookup table is 256kb, which is not trivial but also is well feasible.

We can also use efficient bit tricks to check if a board has been won. We can precompute a set of bitmasks corresponding to each of the 8 possible 3-in-a-row positions:

```
_ _ _     _ _ _      # # #
_ _ _     # # #      _ _ _
# # #     _ _ _      _ _ _


# _ _     _ # _      _ _ #
# _ _     _ # _      _ _ #
# _ _     _ # _      _ _ #


# _ _     _ _ #
_ # _     _ # _
_ _ #     # _ _
```



Checking a single player against a single one of those 8 is simple; We can compute (e.g.) `board.x & mask == mask` and test whether `X` has filled those three squares.

By happy coincidence, 8 winning patterns times 16 bits per pattern is exactly 128 bits, which fits into a single [`xmm`][xmm] register on x86. Using Rust's [`packed_simd`][packed_simd] crate, we can therefore check whether a given player has a winning pattern in an entirely loop-free handful of lines / instructions:

```rust
const WIN_MASKS_SIMD: u16x8 = u16x8::new(0x7, 0x38, 0x1c0, 0x49, 0x92, 0x124, 0x111, 0x54);

fn player_has_win(mask: u16) -> bool {
  u16x8::splat(mask u16) & WIN_MASKS_SIMD)
    .eq(WIN_MASKS_SIMD)
    .any()
}
```

We will use similar patterns later on when analyzing endgames.




[bitboards]: https://www.chessprogramming.org/Bitboards
[taktician-bits]: https://github.com/nelhage/taktician/blob/master/doc/bitboards.md
[local]: ../the-game
[xmm]: https://en.wikibooks.org/wiki/X86_Assembly/SSE
