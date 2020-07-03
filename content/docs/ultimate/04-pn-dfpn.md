---
slug: pn-dfpn
title: The PN-DFPN tree search algorithm
weight: 4
---

# The PN-DFPN proof tree search algorithm

My Ultimate Tic Tac Toe solver uses a parallel variant of [Proof Number search][pns], based largely on [Pawlewicz's SPDFPN][spdfpn] algorithm, which was the state-of-the-art solver for [Hex][hex] as of its publication in 2012.

I have named my variant on SPDFPN "PN-DFPN", since it uses a two-level search, with a traditionall proof-number tree at the root, and concurrent DFPN searches at the leaves of the first-layer tree.

I will describe my solver -- and the various ideas that feed into it -- in this section, attempting to make reference to SPDFPN when appropriate but without fully explaining that prior work.

# Managing parallelism

Tree searches, including Proof Number search and its variants, are in principle inherently parallelizable; at some level of the tree, instead of descending to a single child node, we can descend to multiple nodes in parallel in separate threads.

However, at the same time, a best-first algorithm like Proof Number search is, in another sense, inherently serial; at each step, it selects a (likely unique) most-proving node to process. Expanding this node increases our information about the game tree, giving us a new most-proving node to search.

If we want to search other nodes in parallel with the most-proving node, how are we to select them to maximize the likelihood that searching them will be productive? There is substantial risk that we pick nodes that would _never_ become most-proving, and therefore that the additional work performed by our other threads never actually contributes to the solution of the tree.

We also face the question of how deep to descend into the tree before "splitting" off nodes into multiple parallel search. If we split too deep in the tree, there may not be enough work for threads to do in each child, and we'll spend too much time coordinating; if we split too shallowly, there may not be enough parallelism available, and additionally we increase the risk that parallel threads are searching in unproductive branches of the search tree.

My algorithm uses several notions borrowed from Pawlewicz's SPDFPN, to help manage these decisions.

## Work budgets

We augment the [MID][mid] routine from DFPN to track a `work` counter, which counts the number of recursive `MID` calls performed, and a `work_limit` budget, which will cause the `MID` call to return if its work budget is exceeded, even if its proof numbers are still below threshold.

(Computing "work" is straightforward; `MID` gains an additional return value, corresponding to the work done. It then initializes a local `work` counter to 1, representing its own call, and adds the child's `work` value to it in each iteration of the loop).

This work limit lets us bound the amount of searching done by a single `MID` call, which gives us the ability to speculatively call `MID` on a position, perform some work, and then re-evaluate whether -- based on the results of concurrent parallel searching -- that node is still worth spending time on.

## Virtual proof numbers

In a parallel search, it seems clear that we will want to have one thread searching the current most-proving child. But where in the tree should other threads search?

Building on earlier work, Pawlewicz introduces the notion of "virtual" (dis)proof numbers for a node. In addition to the true proof number values, which we manage as usual, we maintain an overlay layer of "virtual" proof numbers, which we use to manage the parallel search. Initially, virtual proof numbers are identical to real proof numbers. However, when we assign a thread to searching a given node, we update its virtual proof numbers: If `ϕ < δ`, we set the virtual `(ϕ, δ)` to `(0, ∞)`, and otherwise to `(∞, 0)`. In essence, while we are searching a node, we provisionally set its state to "solved," treating it as proved or disproved based on which direction we are closer to proving. We can then propagate virtual PNs up the tree, and select a new most-proving child based on virtual proof numbers to search in a new thread.

## Two-level search tree

My solver, like Pawlewicz' SPDFPN, uses essentially a two-layer search tree. In the first layer, near the root of the search tree, we search in serial using virtual proof numbers in order to find (virtual) MPNs to dispatch to threads. Once a node has been selected for dispatch to a thread, that thread will search it -- up to some specified work budget -- using a vanilla DFPN search. Meanwhile, the serial root node will assign it virtual PNs as described above, and, as long as there are additional worker threads available, will find new MPNs to dispatch to those threads.

How does the first-level search decide whether to descend into a node's children itself, or stop at a node and dispatch that node for parallel searching? Here, again, we use the work budget: we track the total amount of work that has been performed on a given node, and expand a node into its children (in the top-level tree) once a node has exceeded a certain budget of work. This balances the desire to split nodes early -- so we have more available parallelism -- with the desire to defer splitting nodes until we are sure there is enough work in that subtree to be worth multiple cores.

# Putting it together

In my PN-DFPN search, I use a classic Proof Number tree search for the first-layer tree near the root, with nodes augmented with virtual proof numbers. I use a worker pool model, wherein a single thread walks the top-level proof number tree, finds MPNs, and dispatches them to workers via a queue. Workers perform DFPN searches on their nodes up to a fixed work limit, and then return the resulting node as well as its children via  another queue.

When the root thread receives a completed job via a queue, it copies the new proof numbers into its tree. In addition, if the total work on the node exceeds the "split threshold" of work, it expands the node in the first-layer tree, adding the children returned by the worker thread, so that future searches can search those children in parallel.

## Concurrent transposition table

Pawlewicz's SPDFPN uses a shared transposition table with a single global reader-writer lock to manage concurrent accesses between threads. I found this gained insufficient parallelism and contention on that lock limited the avalable parallelism of my solver, so I implemented a custom reader-writer lock which embeds both a [`SeqLock`][seqlock] and a spinlock into 32 unused bits inside _each_ transposition table entry, using Rust's [parking_lot_core][parking_lot_core] crate to manage sleeping on conflicts.


[pns]: /docs/ultimate/pn-search/
[spdfpn]: http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.353.270
[hex]: https://en.wikipedia.org/wiki/Hex_(board_game)
[mid]: docs/ultimate/pn-search/dfpn/#pseudo-code
[seqlock]: https://en.wikipedia.org/wiki/Seqlock
[parking_lot_core]: https://docs.rs/parking_lot_core/0.8.0/parking_lot_core/index.html
