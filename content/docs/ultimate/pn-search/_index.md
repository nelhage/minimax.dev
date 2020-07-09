---
weight: 3
slug: pn-search
title: Proof Number search
---

# Proof Number search

My work on solving Ultimate Tic Tac Toe is based on the Proof Number Search (or "PN Search") family of search algorithms. This family of algorithms has been used to solve many games, including [Checkers][checkers] and [9x9 Hex][hex99], and in endgame solvers for many others, including Chess and Go.

I will present the basic PN algorithm, as well as some of the variants and enhancements that have been developed, when they are relevant to my work.

Much of the material in this section is based on the 2012 survey paper ["Game-tree search using proof numbers:
The first twenty years"][first-20-years] and material from Victor Allis' 1994 thesis ["Searching for Solutions in
Games and Artifcial Intelligence."][searching-for-solutions] I recommend those documents as further jumping-off points for the interested reader.

Unlike the search algorithms in the [minimax][minimax] family, PN search is aimed exclusively at exhaustively searching a game node to solve it, which is to say to prove that the position is a forced win for one side (or a forced draw with optimal play by both players). It can be thought of a [best-first][best-first] search algorithm over the game tree, examining nodes based on an estimate of their promise towards contribuing to a solution to the overall node.

## Win or lose, there is no draw

PN search algorithms aim to produce a single boolean value for the position being examined -- "proven" or "disproven" (aka "forced win" or "forced loss"). They does not contemplate the third possibility present in many games (including Ultimate Tic Tac Toe), of "forced draw under optimal play."

In order to bridge this gap, we conventionally define one player as the "attacker," and define "win" to mean "the attacker wins," and "loss" as "the attacker loses or draws." Thus, if PN search returns "proven," we know the game is a win; if it returns "disproven," we cannot tell if the game is a forced draw or a forced loss.

## The game tree

We will start by considering the general shape of a game tree for a two-player zero-sum game, and then discuss the additional statistics that PN search maintains and how it searches this tree.

The game tree is rooted in some position, with edges corresponding to possible moves, and nodes corresponding to the resulting positions. In a game (like Ultimate Tic Tac Toe) where players alternate moves, each level of the tree alternates which player is to play:

```
(0) X to play                 __A__
                           __/  |  \__
(1) O to play             B     C     D__
                         /|\   / \   /|\ \
(2) X to play           E F G  I J  K L M N

…
```

We will define `X` as the attacker (so that "proven" means "X wins").

we note an alternating pattern of "AND" and "OR" relationships between nodes and their children, corresponding to the player to play:

- If `A` is proven, it means that, starting from `A`, `X` must have some move she can make, such that the resulting position is still a win for `X`. So we have `A = OR(B, C, D)` -- to prove `A`, it is sufficient to prove only one of its children.
- However, for `B` to be proven, it must be the case that no move `O` can make from that position will save him. If just one of `E`, `F`, and `G` saves `O` from defeat, `O` will make the move that arrives at that node. So we have `B = AND(E, F, G)`.

Via [De Morgan][demorgan] or just by repeating our analysis in reverse, *dis*proving `A` (or any node with `X` to play) requires disproving all of its children, and *dis*proving `B` (or any node with `O` to play) requires *dis*proving only one of its children.

## Iterative construction

The basic shape of PN search is to incrementally instantiate the search tree in memory, repeatedly heuristically selecting a child (known as the "most-proving node") to expand which is hoped to make progress towards solving the root.

Because we expand the tree incrementally, the in-memory tree will have three types of nodes:

Terminal nodes
: Nodes at which the game is over – won, lost or drawn. These nodes have no children.

Internal nodes
: Nodes at which the game is still in play, and for which we have already instantiated their children and added them to the tree.

Unexpanded nodes
: Nodes at which the game is still in play, but for which we have not yet instantiated their children.

## Proof numbers

In order to chose a most-proving node, PN search maintains two key statistics at each node, called the "proof number" and "disproof" number, or "pn" and "dpn" for short. These numbers are constructed such that the (dis)proof number of a node is a lower bound on the number of descendants of that node which will have to be examined in order to (dis)prove that node.

Let's consider the above game tree, and consider the (d)pn of the root in light of the AND/OR property previously discussed.

As discussed, to prove `A` it is sufficient to prove any one of its children, but proving that child will require proving all of its children. Thus, proving `A` requires that for *some* node in row (1), we prove all of that node's children in row (2).

The node in row (1) with the fewest children is `C`; thus, proving both `I` and `J` would suffice to prove `A`, and we have `pn(A) = 2`.

Conversely, disproving `A` would require disproving all of `B`, `C`, and `D`, but disproving each of those nodes would only require disproving any one of their children; e.g. disproving `E`, `J`, and `L` would suffice to disprove `A`. So we have `dpn(A) = 3`.

In general, we find that the `pn` of an internal OR node is equal to the minimum `pn` of any of its children (since we need only prove one child), whereas its `dpn` is the **sum** of its childrens' `dpn`s (since disproof requires disproving all of its children). The converse is true for AND nodes. Formulaically (let {{<katex>}}\operatorname{succ}(N){{</katex>}} be the set of all of a node's children):

- For an internal `OR` node (attacker to move):
{{< katex display >}}
\begin{aligned}
pn(N)  &= \min_{c\in \operatorname{succ}(N)}pn(c) \\
dpn(N) &= \sum_{c\in \operatorname{succ}(N)}dpn(c)
\end{aligned}
{{< /katex >}}
- For an internal `AND` node (defender to move):
{{< katex display >}}
\begin{aligned}
pn(N)  &= \sum_{c\in \operatorname{succ}(N)}pn(c) \\
dpn(N) &= \min_{c\in \operatorname{succ}(N)}dpn(c)
\end{aligned}
{{< /katex >}}

For terminal nodes, we set the proof numbers directly based on the game's outcome:
- If the attacker has won we have `pn=0` and `dpn=∞`
- If the defender has won or the game is drawn, we have `pn=∞` and `dpn=0`

For unexpanded noded, we have some flexibility in assigning proof numbers; in the general case, we must define an _initialization rule_ which determines how we initialize proof numbers. The most conservative rule is to set `pn = dpn = 1` -- recall that the (d)pn's are a lower bound on the number of nodes that must be proved, and `1` is necessarily a lower bound for a nonterminal node. The initialization rule, however, is one opportunity to inject game-specific heuristics into PN search. One common heuristic is to initialize `pn` and `dpn` based on the number of available moves from the position, in cases where that is sufficiently cheap to compute.

## The most-proving node

As mentioned, at each iteration, PN search selects a "most-proving (leaf) node" (an "MPN") to expand. The goal of selecting an MPN is to select a node which, if proved or disproved, would propagate all the way back to the root and impact the root's pn or dpn.

We find the MPN by recursive search from the root, according to the following logic:

- At an OR node, altering the `dpn` of any child would impact the root's `dpn`. However, only the child with minimal `pn` has direct impact on the root's `pn`; updating any other node's `pn` can only impact the root if it becomes the new minimum. Thus, from an OR node, we descend to the child with minimum `pn`; any update to this node's proof numbers will update the root's proof numbers (or change the MPN, in the event that the child's new `pn` is no longer minimal among its peers).
- Conversely, at an `AND` node, we descend to the child with minimal `dpn`, by similar logic.

By recursively following this rule until we arrive at a leaf (unexpanded) node, we find a most-proving node. We then expand this node by constructing its children and evaluating them and assigning initial proof numbers (either `0/∞` if the node is terminal, or based on the initialization rule otherwise). We then update proof numbers along the path to the root. If the root is solved, we are done; otherwise, we select a new MPN and repeat until we exceed our budget for either time or memory, or solve the root.

### A sketch of PN search

I will not present full pseudo-code (see [Kishimoto et al][first-20-years] for one such presentation), but I will sketch the full PNS algorithm:

- Initialization: We create the root node of the tree
- Search: We repeat the following loop until either the root is solved (`pn=0` or `dpn=0`), or until we exceed a specifide budget for search time or memory:
  - We select an MPN as described above
  - We expand the MPN by creating tree nodes, one for each legal move from the MPN
  - We evaluate those children, assigning proof numbers based on either game result, or an initialization heuristic
  - We backpropagate, updating proof numbers for every node on the path from the root to the MPN

You can also [read the source][source] of my PN search algorithm for Ultimate Tic Tac Toe, which I implemented on the way to [my current solver][pn-dfpn].

[checkers]: https://science.sciencemag.org/content/317/5844/1518
[hex99]: http://webdocs.cs.ualberta.ca/~hayward/papers/pawlhayw.pdf
[first-20-years]: https://webdocs.cs.ualberta.ca/~mmueller/ps/ICGA2012PNS.pdf
[searching-for-solutions]: https://project.dke.maastrichtuniversity.nl/games/files/phd/SearchingForSolutions.pdf
[minimax]: https://en.wikipedia.org/wiki/Minimax#Minimax_algorithm_with_alternate_moves
[best-first]: https://en.wikipedia.org/wiki/Best-first_search
[demorgan]: https://en.wikipedia.org/wiki/De_Morgan%27s_laws
[pn-dfpn]: ../pn-dfpn/
[source]: https://github.com/nelhage/ultimattt/blob/master/src/lib/prove/pn.rs
