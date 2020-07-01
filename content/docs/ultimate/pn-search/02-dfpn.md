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

In vanilla PN search, we would descend to `B` (it has the minimal δ). This descent would expand some child, update some number of proof numbers on the path from B to the MPN, and then eventually ascend up through the tree to `A` before ultimately returning to the root.

In this case, we would have no guarantee that this process will update `A`'s or even `B`'s proof numbers; it might update some children but not propagate up to `A` or `B`. If we are not storing the entire subtree, but only tracking children on the stack during each recursive call, we will have no way to store the updated proof numbers, and the descent will be ineffectual.

What we want to do is to instead descend to `B`, and recursively perform a search rooted at `B` _until the result has implications for A_. If, for instance, we search at B and return a new `(φ, δ)` pair of `(2, 4)`, then we want to return to `A`, since `C` is now the most-proving child and we should switch to examining it instead.

So what does it mean to search `B` "until the result matters"? Recall from [last time][phidelta] the definitions of φ and δ:

{{<katex>}}
\begin{aligned}
\phi(N)  &= \min_{c\in \operatorname{succ}(N)}\delta(c) \\
\delta(N) &= \sum_{c\in \operatorname{succ}(N)}\phi(c)
\end{aligned}
{{</katex>}}

As well as the fact that the most-proving child is the(a) child with minimal δ amongst its siblings.

The result of a subtree search can matter in three ways:
1. If `B`'s δ value rises such that `B` is no longer the most-proving child of `A`, we need to return to `A` and select a new child.
2. If `B`'s φ value rises, it will increase `A`'s δ value. If that results in `A` itself no longer being the most-proving child of _its_ parent, we need to ascend from _A_ itself.
3. If `B`s δ rises but it remains the most-proving child, that will increase `A`'s φ value. If that in turn increase `A`'s φ value such that it triggers the previous criteria for `A` itself, we need to return.

We are now ready to define DFPN. The core routine of a DFPN search is a routine `MID(position, limit) -> pns`[^mid], which takes in a game position and a pair of _threshold_ values, `(φₜ, δₜ)`, at which `MID` should return if its updated proof numbers meet or exceed either limit[^solved]. `MID` recursively searches the subtree rooted at `position` until it produces a `(φ, δ)` pair for that node with `φₜ ≥ ϕ || δ ≥ δₜ`, at which point it will return those values.

In Pythonic pseudo-code, `MID` looks something like:


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

The key to the routine is the block labeled "Compute thresholds for the child call". `MID` selects a most-proving child and recurses on it, but in order to do so, it must compute a new set of thresholds for that call. Where do those values come from? Let's consider the conditions outlined above:

- Condition (1) implies the child call should return if `child_delta` is strictly greater than `delta_2` (the second-smallest delta value among our children).
- Condition (2) implies the child call should return if `child_phi` is large enough that `delta >= delta_t`. This in turn implies `child_phi + (sum of other children) >= limit.phi`. We can compute the sum of the other children as `delta - phi_c` and move it across the `>=` to arrive at `child_limit.phi = limit.phi - (delta - phi_c)`.
- Condition (3) implies the child call should return if `child_delta > limit.phi`.

Conditions (1) and (3) both constrain `child_delta`, so we have to pick the most-constraining, which is the minimum of the two.

To kick off the DFPN search, we simply start with `MID(root, (∞, ∞))`.

## Transposition tables

Because of MID's recursive iterative-deepening structure, it (as written above) repeatedly expands the same nodes many, many times as it improves the computed proof numbers. I haven't done the analysis but I suspect the above algorithm of being exponentially slower than proof-number search in number of nodes visited, rendering it essentially unusable as-is.

DFPN is thus always used in conjunction with a transposition table to store computed proof numbers so far.

A transposition table is just a fixed-size lossy hash table, indexed by board position. Typical implementations probe some constant number of table buckets on lookup, and on write, choose one of those buckets to replace with the new entry.

By storing entries (and their proof numbers) in a transposition table, we can re-use most of the work from previous calls to `MID`, restoring the algorithm to the realm of the practical. However, because DFPN relies on the table only as a cache, and not for correctness, DFPN can (unlike PN search) continue to make progress if the search tree exceeds available memory, especially when augmented with some additional tricks and heuristics.


## A note on this presentation

I learned about DFPN -- as with much of the material here -- primarily from [Kishimoto et al][first-20-years]'s excellent 2012 survey of Proof Number search and its variants.

However, I have deviated substantially here from their presentation of the algorithm. I have two main critiques about their presentation -- and nearly every other presentation I could find -- which I have attempted to remedy here.

First, it took me a long time to understand how one arrives at DFPN and why it transforms PN search into a depth-first algorithm. The cutoff computation detailed above is presented largely in terms of an additional optmization on top of PN search, which enables the search to stay deeper for longer, and the connection from that observation to depth-first search and iterative deepening is not made explicit. I have tried to draw out that connection more explicitly here and motivate the development of DFPN further.

Second, the presentation in Kishimoto et al ties together the transition to multiple-iterative-deepening with the addition of a transposition table, and also relies on the table's presence for correctness of the algorithm; In their presentation, if the transposition table discards an unlucky series of writes, `MID` will enter an infinite loop and fail to make progress. Depending on the details, this may or may not be a concern in practice, but I found it very confusing when attempting to understand the workings of the algorithm; if the whole point of DFPN is to continue to work when the search tree exceeds memory, why are we relying on the transposition table for correctness instead of merely as a cache?

After thinking through the algorithm, reading at least one existant implementation, and implementing my own, I realized that the above implementation strategy and presentation avoids this problem, and I hope it may also avoid confusion for readers.

[idastar]: https://en.wikipedia.org/wiki/Iterative_deepening_A*
[phidelta]: ../variants/#%cf%86-%ce%b4-search
[first-20-years]: https://webdocs.cs.ualberta.ca/~mmueller/ps/ICGA2012PNS.pdf
[^mid]: "MID" stands for "Multiple iterative deepening", indicating that we're doing a form of iterative deepening, but we're doing it at _each level_ of the search tree.
[^solved]: (Recall that solved nodes have either `φ=∞` or `δ=∞`, so a solved node will always exceed any threshold provided).
