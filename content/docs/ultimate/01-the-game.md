---
weight: 1
slug: the-game
title: Rules of the game
---

# Ultimate Tic Tac Toe

[Wikipedia has a decent writeup of Ultimate Tic Tac Toe][wikipedia], but I will also include a short writeup here.

The game of Ultimate Tic Tac Toe is played on a 3-by-3 grid where each grid square is itself a Tic Tac Toe board:


```
.  .  . | .  .  . | .  .  .
.  .  . | .  .  . | .  .  .
.  .  . | .  .  . | .  .  .
--------+---------+--------
.  .  . | .  .  . | .  .  .
.  .  . | .  .  . | .  .  .
.  .  . | .  .  . | .  .  .
--------+---------+--------
.  .  . | .  .  . | .  .  .
.  .  . | .  .  . | .  .  .
.  .  . | .  .  . | .  .  .
```

We'll call the overall grid the "global" board or game, and each of the 9 smaller games as a "local" board or game.

On each turn, each player plays in a square of a local board, constrained by the rules as explained in a moment. If a player wins a local board (by the usual rules of Tic Tac Toe), that local board is marked as belonging to that player in the global board. The goal of the game is to win the global game of Tic Tac Toe by connecting three squares in a row, which thus requires winning at least three local games.

The complexity of the game derive from the interaction between the local boards and the global board, as well as the core rule of play:

- On the initial move of the game, `X` has their choice of any of the 81 squares on the board to play.
- After that move, however, each player must play in the local board corresponding to the relative position of play of the previous player in their own local board. For instance, if `X` starts with this move:

```
.  .  . | .  .  . | _  _  _
.  .  . | .  .  . | _  _  _
.  .  . | .  .  . | _  _  _
--------+---------+--------
.  .  . | .  .  X | .  .  .
.  .  . | .  .  . | .  .  .
.  .  . | .  .  . | .  .  .
--------+---------+--------
.  .  . | .  .  . | .  .  .
.  .  . | .  .  . | .  .  .
.  .  . | .  .  . | .  .  .
```

Then `O` is constrained to play in the top-right local board (marked by `_` characters above), since `X` played in the top-right square of their local board.

Thus, each move serves both to make progress in a local game, and also to constrain the opposing player's following move, resulting in a continual interplay between tactical and strategic considerations.

Once a local board is won (or drawn), any player who is "sent" to that board may make an unconstrained move, playing into the local board of their choice.


[wikipedia]: https://en.wikipedia.org/wiki/Ultimate_tic-tac-toe#Rules
