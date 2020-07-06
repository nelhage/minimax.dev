---
weight: 2
slug: dfpn
title: "Depth-First Proof Number Search"
---

# Depth-First Proof Number Search

Depth-First Proof Number Search (DFPN) is an extension of Proof Number Search to convert to a depth-first algorithm which does not require reifying the entire search tree. In this section I will present DFPN and attempt to motivate the way in which it works.

## Iterative deepening

DFPN uses a form of iterative deepening, in the style of most minimax/α-β engines or [IDA\*][idastar].

The general idea of iterative deepening algorithms is to convert a memory-intensive breadth- or best-first search into repeated depth-first searches, limiting each round of depth-first search to a "budget" of some sort, which we increase each round. The effective result is that we expand nodes in the same order as the best-first algorithm but at a much-decreased memory cost. In exchange for this memory efficiency, we expend more compute time, since we will re-visit earlier layers of the search tree many times.

In vanilla iterative deepening, our budget is the search depth; we run a depth-first search to depth 1, and then 2, and then 3, and so on until we find the solution or exceed a time budget.

In IDA\*, we use the A\* heuristic cost estimate as our budget, searching in a depth-first fashion to a maximum cost-estimate, and increasing that cost estimate on each call to the iterative search.

The question, then, becomes how to augment Proof Number search (a) to behave in a depth-first manner, and (b) how to define and manage a budget to terminate each round of depth-first search.

## Getting to DFPN

Our first observation is that Proof Number search already has something of the depth-first nature. While Proof Number search does retain the entire search tree, it does not maintain an explicit queue or priority queue of nodes to search, but instead each iteration proceeds from the root and selects a single child, proceeding to the leaves of the search tree in a depth-first fashion, repeating this cycle until the algorithm terminates.

So the basic structure of PN is ripe for conversion to iterative deepening; the question, then, is how to convert it to not require reifying our entire search tree.

Let's suppose we're examining a node in a proof-number search tree. We have constructed an array of children (possible moves from this position), and we have computed `(φ, δ)` proof numbers for each, which in turn generates a `(φ, δ)` value for our own node (This whole section will work in a [φ-δ][phidelta] fashion, with each node annotated with its `(φ, δ)` values, removing the need to annotate AND vs OR nodes)
:

```
node(φ,δ)

           A(2,2)
          / \
    B(1,2)   C(1,3)
```

In vanilla PN search, we would descend to `B` (it has the minimal δ). We would expand some child, update some number of proof numbers on the path from B to the MPN, and then eventually ascend up through the tree to `A` before ultimately returning to the root.

In general, this expansion might not update `A`'s or even `B`'s proof numbers; it might update some children but not propagate up to `A` or `B`. (We talked about this possibility [last time][staying-deep]).

If we are not storing the entire subtree, but only tracking children on the stack during each recursive call, we will have no way to store the updated proof numbers produced by this descent, and no way to make progress.

From the perspective of a search rooted at `A`, what we instead want to do is to descend to `B`, and recursively perform a search rooted at `B` _until the result has implications for A_. If, for instance, B's proof numbers change to `(2, 4)`, then we want to return to `A`, since `C` is now the most-proving child and we should switch to examining it instead.

This gets us close to the DFPN algorithm. The core routine of a DFPN search is a routine `MID(position, limit) -> pns`[^mid], which takes in a game position and a pair of _threshold_ values, `(φₜ, δₜ)`. `MID` will search rooted at `position` until the proof numbers at that position equal or exceed either limit value[^solved] (i.e. `φₜ ≥ ϕ || δ ≥ δₜ`). At this point, `MID` will return the updated proof numbers for that position.

## Selecting thresholds

So how does `MID` choose thresholds to pass to its recursive children? To determine this, we need to examine what it means to search to search `B` "until the result matters at `A`." Recall from [last time][phidelta] the definitions of φ and δ:

{{<katex>}}
\begin{aligned}
\phi(N)  &= \min_{c\in \operatorname{succ}(N)}\delta(c) \\
\delta(N) &= \sum_{c\in \operatorname{succ}(N)}\phi(c)
\end{aligned}
{{</katex>}}

And recall that the most-proving child is the(a, if there are several) child with minimal δ amongst its siblings.

The result of a subtree search can matter in three ways:
1. If `B`'s δ value rises such that `B` is no longer the most-proving child of `A`, we need to return to `A` and select a new child.
2. If `B`'s φ value rises, it will increase `A`'s δ value (that being the sum of its childrens' φs). If that results in `A` itself no longer being the most-proving child of _its_ parent, we need to ascend to (and, indeed, above) `A` itself.
3. If `B`s δ rises but it remains the most-proving child, that will increase `A`'s φ value. If that in turn increase `A`'s φ value such that it triggers the previous criteria for `A` itself, we need to return.

Combining these criteria, we can arrive at the `(ϕₜ, δₜ)` thresholds `MID` should pass to a recursive call when examining a child.

Let `(ϕ, δ)` be the proof numbers so far for the current node. Let `(ϕₜ, δₜ)` be the bounds to the current call. Let `(ϕ₁, δ₁)` be the proof numbers for the most-proving child, and `δ₂` the `δ` value for the child with the second-smallest δ (noting that we may have `δ₁ = δ₂` in the case of ties).

Examining the previous conditions:

- Condition (1) implies the child call should return if `δ(child)` is strictly greater than `δ₂`, which is to say weakly greater than `δ₂+1`.
- Condition (2) implies the child call should return if `ϕ(child)` is large enough that `δ ≥ δₜ`. This in turn implies `ϕ(child) + (sum of our other children) ≥ δₜ`. We can compute the sum of our other children as `δ - ϕ₁`, and move that across the `≥` to arrive at `ϕₜ(child) = δₜ - (δ - ϕ₁)`.
- Condition (3) implies the child call should return if `δ(child) > ϕₜ`.

Conditions (1) and (3) both constrain `δ(child)`, so we have to pick the most-constraining, which is the minimum of the two: `δₜ(child) = min(δ₂+1, ϕₜ)`.

## Pseudo-code

We're now ready to sketch out `MID` in its entirety. Working in Pythonic pseudo-code, we arrive at something like this:


```python
INFINITY = 1 << 60

def MID(position, limit):
  children = [
    position.make_move(m) for m in position.legal_moves()
  ]
  child_pns = [
    initialize_pns(pos) for pos in children
  ]
  while True:
    phi = min(pns.delta for pn in child_pns)
    delta = sum(pns.phi for pn in child_pns)
    if phi >= limit.phi or delta >= limit.delta:
      return PN(phi=phi, delta=delta)

    # Compute thresholds for the child call
    min_idx = None
    delta_min = delta_2 = INFINITY
    phi_c = None
    for (ch, i) in enumerate(child_pns):
      if ch.delta < delta_min:
        delta_2 = delta_min
        delta_min = ch.delta
        phi_c = ch.phi
        min_idx = i
      elsif ch.delta < delta_2:
        delta_2 = delta_min
    child_limits = PN(
      phi = limit.delta - (delta - phi_c),
      delta = min(limit.phi, delta_2 + 1)
    )
    child_pns[i] = MID(children[i], child_limits)
```

To kick off the DFPN search, we simply start with `MID(root, (∞, ∞))`.

## Transposition tables

Because of MID's recursive iterative-deepening structure, it will repeatedly expands the same nodes many, many times as it improves the computed proof numbers. I haven't fully done the analysis but I suspect the above algorithm of being exponentially slower than proof-number search in number of nodes visited, rendering it essentially unusable.

Thus, DFPN is always used in conjunction with a transposition table, which stores the proof numbers computed so far for each node in the tree, allowing repeated calls to `MID` to re-use past work.

I will talk about transposition tables -- and my implementation -- more elsewhere, but in short, a transposition table is a fixed-size lossy hash table. It supports the operations `store(position, data)` and `get(position)`, with the property that `get(position)` following a `store(position, …)` will **usually** return the stored data, but it may not, because the table will delete entries and/or ignore `store`s in order to maintain a fixed size. I will talk elsewhere about the details of transposition table implementation and some of the choices in which entries to keep or discard.

By storing proof numbers in a transposition table, we can re-use most of the work from previous calls to `MID`, restoring the algorithm to the practical. However, because DFPN, as constructed here, relies on the table only as a cache, and not for correctness, DFPN can (unlike PN search) continue to make progress if the search tree exceeds available memory, especially when augmented with some additional tricks and heuristics.

The changes to the algorithm above to use a table are small; in essence, we replace `initialize_pns(pos)` with `table.get(pos) or initialize_pns(pos)`, and we add a `table.save(position, (phi, delta))` call just after the computation of `phi` and `delta` in the inner loop.

You can [read the source][source] of my DFPN search algorithm to put all the pieces together; It is exposed both as a standalone algorithm and used as a subroutine in [my current solver][pn-dfpn].

[pn-dfpn]: ../../pn-dfpn/
[source]: https://github.com/nelhage/ultimattt/blob/master/src/lib/prove/dfpn.rs

# A note on this presentation

I learned about DFPN -- as with much of the material here -- primarily from [Kishimoto et al][first-20-years]'s excellent 2012 survey of Proof Number search and its variants.

However, I have deviated substantially here from their presentation of the algorithm, and I want to explore some of the distinctions here.

Kishimito et al (and every other presentation I could find of DFPN) present the switch to depth-first iterative deepening concurrently with the addition of a transposition table. While this presentation is logical in the sense that you would never use DFPN without a transposition table, I found it confusing, since it was hard to tease apart why the core algorithm works, since the deepening criteria is conflated with the hash table. I find the two-step presentation above very helpful for understanding _why_ DFPN works.

Secondly, the table in Kishimito's presentation is "load-bearing"; `MID` relies on the table to store and return proof numbers to make progress. In essence, the he replaces the lines
```python
    phi = min(pns.delta for pn in child_pns)
    delta = sum(pns.phi for pn in child_pns)
```
with
```python
    phi = min(table.get(pos).delta for pos in children)
    delta = sum(table.get(pos).phi for pos in children)
```

This translation is correct as long as the table never discards writes, but the whole point of a transposition table is that it is a fixed finite size and *does* sometimes discard writes. Kishimoto's version may cease to make progress if the search tree exceeds memory size, while my presentation above should only suffer a slowdown and continue to make progress.

That said, the slowdown can be exponentially bad in practice, which isn't much better than stopping entirely, so I suspect this distinction is somewhat academic the algorithm as presented above. However, I have actually run into a concrete version of this problem during the development of parallel DFPN algorithms, and so I consider it an important point to address.


[idastar]: https://en.wikipedia.org/wiki/Iterative_deepening_A*
[phidelta]: ../variants/#%cf%86-%ce%b4-search
[staying-deep]: ../variants/#staying-deep-in-the-tree
[first-20-years]: https://webdocs.cs.ualberta.ca/~mmueller/ps/ICGA2012PNS.pdf
[^mid]: "MID" stands for "Multiple iterative deepening", indicating that we're doing a form of iterative deepening, but we're doing it at _each level_ of the search tree.
[^solved]: (Recall that solved nodes have either `φ=∞` or `δ=∞`, so a solved node will always exceed any threshold provided).
