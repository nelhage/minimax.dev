---
slug: hashing
title: Zobrist Hashing
---

# Zobrist hashing

Both minimax search and [Depth-First Proof Number Search][dfpn] benefit from an efficient hash function on board positions in order to store them into a [transposition table][tt].

I use a variant of [Zobrist hashing][zobrist] hashing, a technique invented for chess which produces a good hash value and is easily incrementally updated as moves are made.

To produce a Zobrist hash, I generated, offline, the following sets of 64-bit random numbers:

- 2*81 numbers, one for each (local square, player) combination
- 3 * 9 numbers, for `X`, `O`, and "Draw" on each global board
- 9 numbers, one for each global board that the current player could be "sent" to
- One random number, indicating which player is to play.

In order to compute a Zobrist hash, we select all of the pregenerated numbers corresponding to the facts of the board we are hashing, and exclusive-or them all together.

This representation has the property that it is easily incrementally computed. We store the 64-bit current hash into the `Position` struct, and, on move, we update it by:

- We XOR the value corresponding to the local square the player just played on.
- If the player just completed a local board, we XOR in the corresponding value from the global board table.
- If the player who just played was "sent" to a board, we XOR in the value for that board, to "remove" it from the hash.
- If the player has "sent" the next player to a board, we XOR in the value of that board.
- We XOR in the "player-to-play" value, essentially toggling it back and forth on each move.

Because `XOR` is commutative and associative, and because it is its own inverse, this has the property of producing the same 64-bit hash value from the same board position, no matter what sequence of moves reached it.

As an additional optimization, when a player wins or draws a global board, we iterate over all the played squares on that board, and we XOR them back into the hash, effectively "removing" them from the hash. This has the property that once a local board is closed, we treat it identically no matter how it was won or which moves were played into it.


[dfpn]: /docs/ultimate/pn-search/dfpn/
[tt]: https://www.chessprogramming.org/Transposition_Table
[zobrist]: https://www.chessprogramming.org/Zobrist_Hashing
