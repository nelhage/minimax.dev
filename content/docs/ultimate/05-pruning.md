---
weight: 5
slug: pruning
title: Pruning and positional analysis
---

# Positional analysis and tree pruning

Proof Number search and its variants can almost always be productively combined with domain-specific analysis of a game that can solve endgames or prune some moves as irrelevant without doing an explicit search.

This analysis typically takes one of two forms:

Endgame databases
: Especially for games like chess or checkers, where pieces are removed from the board as the game progresses, it is feasible to build exhaustive databases of all positions with _k_ or fewer pieces remaining, as well as their outcome. Then, during a search, if we reach a position with only that many  pieces on the board, we can do a database lookup and determine the answer directly.

Positional analysis
: For some games, we can prove that certain positions are winning or losing analytically, or that certain moves dominate others. Much work has been done in the field of [combinatorial game theory][cgt], including for [connection games][connection] and [Nimbers][nimbers], which can often provide the basis of such analyses. In the game of [Hex][hex], which has provided an active area of research for solution engines, much of the work has been on developing improved "virtual connection engines," which can statically prove positions, or prove that a player must make a given move (or one of a set of moves) in order to avoid a loss. Such engines drastically shrink the game tree that must be searched by the generic tree search algorithm.

# Positional analysis for Ultimate Tic Tac Toe

I have, to date, not done an enormous amount of work on positional analysis of Ultimate Tic Tac Toe. I believe that devoting more work here and implementing more-effective tree pruning will be the highest-leverage work for making progress towards solving the complete game.

## Critical move analysis

I have, however, implemented one form of analysis, around what I refer to as "critical squares."

In lategame Ultimate Tic Tac Toe games, it is not uncommon that one player is a single move away from winning, if only they could play in a given board. For instance, consider the following position:

```
        | _  _  _ | O  _  _
        | _  _  _ | _  X  X
X  X  X | X  _  X | X  X  _
--------+---------+--------
_  _  _ | O  _  O | _  O  O
_  _  X | _  X  X | X  X  O
O  _  _ | _  O  _ | _  X  _
--------+---------+--------
O       | O  O  O | _  _  O
   O    |         | _  _  O
      O |         | X  _ (_)
```

(To enhance clarity, I've deleted all moves except the winning line from local boards that are won; `O` has won two local baords, and `X` one.)

If `O` is ever allowed to play in the bottom-right board, she will play in the marked square and win the game. `X`, thus, in order to keep the game going, is constrained to only play moves that do not allow `O` to play there.

[Recall][game-rules] that if a player is "sent" to a local board that has been won or drawn, she has the choice to play into any open square in the entire game.

Those facts combined means that `X` must never "send" O to either the bottom-right board, or to any solved board. We can draw this schematically by annotating the relative positions that `X` must avoid playing:

```
# . .
. . .
# # #
```

If `X` ever plays into one of those squares -- in any local baord -- he loses the game[^winning]. We can thus, whenever it is `X`'s turn to play, immediately exclude those moves from the search tree!

Furthermore, we can do one level of implicit lookahead whenever it is `X`'s move to play: If any local board has _only_ those squares open, it is losing for `O` to be forced to play there. Thus, if any such local boards exist, the corresponding positions become _winning_ for `X`.

In particular, if we look at the center-right board, we note that the only open squares correspond to those marked on our diagram above. Thus, if `X` is ever allowed to play into the center-right position in any local board, he will also win, with no search required.

This is a place where the [bitboard][bitboard] representation in my engine makes these kinds of queries very efficient. Once we've computed `O`'s "losing set" as a bitmask, we can easily subtract those moves from a board's "open square" set by a bitwise AND. And if the result is zero, that means all moves are losing for `O`, which is useful when `X` is performing the above lookahead.

Furthermore, while I haven't had the need to implement this optimization yet, we should be able to use the AVX2 256-bit instructions to encode all 9 boards into a a single `YMM` register, and perform these kinds of tests on each board concurrently.

## Endgame databases

I have not yet attempted to perform the exact combinatorics to calculate the size of the Ultimate Tic Tac Toe endgame, but I currently do not see a clear way to build endgame databases. As the game progresses, there are typically _more_ marks on the board, increasing rather than ever decreasing the number of possible boards.

Winning a local board does collapse the search space, since once a local board is won, it can be represented as a single symbol and the individual moves on that board no longer matter. However, in my searches so far, most games do not complete that many local boards before being one by one player or another, suggesting that this observation doesn't help us that much.

[game-rules]: /docs/ultimate/the-game/
[cgt]: https://en.wikipedia.org/wiki/Combinatorial_game_theory
[connection]: https://en.wikipedia.org/wiki/Connection_game
[nimbers]: https://en.wikipedia.org/wiki/Nimber
[hex]: https://en.wikipedia.org/wiki/Hex_(board_game)
[bitboard]: /docs/ultimate/efficient-representation/#our-representation

[^winning]: There is one important caveat here: `X` may play in such a square _if that move itself wins the game_.
