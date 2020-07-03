---
title: Solving Ultimate Tic Tac Toe
---

# Work towards solving Ultimate Tic Tac Toe

Over the last few months, I've been working on solving [Ultimate Tic Tac Toe][wikipedia], also known as (Tic Tac Toe)². I've made considerable progress, but, as of this writing, am still some distance away from the solution being feasible in an amount of compute time and money I'm willing to spend. This section of the site is dedicated to documenting my work so far and some next steps.

Solving Ultimate Tic Tac Toe isn't a particularly important goal in and of itself, but I've found this project a great opportunity to learn about a fairly wide range of topics; I'm hopeful this writeup can bring some of those lessons to others who have similar interests, or just who want to follow along with a nerdy deep-dive into game tree search and high-performance Rust while we're all stuck at home.

# Progress

As of this writing, I have a high-performance Ultimate Tic Tac Toe solver written in Rust. This solver includes:

- A [high performance implementation][efficient] of an Ultimate Tic Tac Toe engine.
- An [efficient parallel proof tree search algorithm][pn-dfpn], consisting of a combined two-level [Proof Number search][pns] and [Depth-First Proof Number Search][dfpn] search.
- A high-performance parallel transposition table.
- An endgame analysis engine capable of solving some endgames without tree search, in order to prune the search tree.

The solver is presently capable of solving Ultimate Tic Tac Toe positions after about 20 ply (10 moves by each player) in a few hours of search on my Ryzen 3900X desktop. I (very roughly) estimate this implies a total computational cost of a few hundred million CPU-hours to solve the whole game without further optimization. CPU time on AWS costs something like 2 cents an hour, suggesting a cost in the $2M - $10M range. I thus believe the solution is solidly within the realm of "technically feasible", but certainly well outside my budget. Further optimizations will be required to knock off a few more orders of magnitude in order to complete the project.

# Reading about my solver

- If you're unfamiliar with the game of Ultimate Tic Tac Toe, start with [my writeup](the-game) of the game.
- The core of my solver is based on the [Proof-Number search][pns] family of algorithms. You can read about that family at the previous link, or jump to [the writeup of my solver][pn-dfpn].
- If you're curious about my efficient implementation of Ultimate Tic Tac Toe, including what I suspect of being the first-ever SIMD Tic Tac Toe implementation, [find that here][efficient].


[wikipedia]: https://en.wikipedia.org/wiki/Ultimate_tic-tac-toe
[efficient]: efficient-representation/
[pns]: pn-search/
[dfpn]: pn-search/dfpn/
[pn-dfpn]: pn-dfpn/
