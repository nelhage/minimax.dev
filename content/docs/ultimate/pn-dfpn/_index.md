---
slug: pn-dfpn
title: Parallel proof tree search
weight: 4
---

# Parallelism in my solver

My Ultimate Tic Tac Toe solver uses a parallel variant of [Proof Number search][pns], based largely on [Pawlewicz's SPDFPN][spdfpn] algorithm, which was the state-of-the-art solver for [Hex][hex] as of its publication in 2012.

I have named my variant on SPDFPN "PN-DFPN", since it uses a two-level search, with a traditional proof-number tree at the root, and concurrent DFPN searches at the leaves of the first-layer tree.

In order to explain PN-DFPN, I will build up the key ideas behind it in this section, which are mostly borrowed from Pawlewicz's SPDFPN.

# Managing parallelism

Tree searches, including Proof Number search and its variants, are inherently parallelizable; At each level of the search tree we have multiple children to consider, and we can -- in principle -- consider multiple children in parallel on separate cores.

At the same time, however, a best-first algorithm like Proof Number search is inherently somewhat serial: the choice of children to expand relies on the results of search to date in order to select a most-proving node.

If we want to search other nodes in parallel with the most-proving node, how are we to select them to maximize the returns from seaching them? There is substantial risk that we expand nodes that would _never_ become most-proving in a serial algorithm, and thus that the additional work performed by our other threads never actually contributes to the solution of the tree.

Similarly, we face the question of how deep to descend into the tree before "splitting" off nodes into multiple parallel search. If we split too deep in the tree, there may not be enough work for threads to do in each child, and we'll spend too much time coordinating; if we split too shallowly, there may not be enough parallelism available, and additionally we increase the risk that parallel threads are searching in unproductive branches of the search tree.

My algorithm uses several notions borrowed from Pawlewicz's SPDFPN to manage these search decisions.

## Work budgets

As in SPDFPN, we augment the [MID][mid] routine from DFPN to track a `work` counter, which counts the number of recursive `MID` calls performed, and a `work_limit` parameter, which provides a budget: `MID` will return if it performs more work than its budget, even if its proof numbers are still below threshold.

(Computing "work" is straightforward; `MID` gains an additional return value, corresponding to the work done. It then initializes a local `work` counter to 1, representing its own call, and adds the child's `work` value to it in each iteration of the loop).

This work limit lets us bound the amount of searching done by a single `MID` call, which gives us the ability to speculatively call `MID` on a position in a thread, perform some work, and then re-evaluate whether -- based on the results of concurrent parallel searching -- that node is still worth spending time on.

## Virtual proof numbers

In a parallel search, it seems clear that we will want to have one thread searching the current most-proving child. But where in the tree should other threads search?

Building on earlier work, Pawlewicz introduces the notion of "virtual" (dis)proof numbers for a node. In addition to the true proof number values, which we manage as usual, we maintain an overlay layer of "virtual" proof numbers, which we use to manage the parallel search.

Initially, virtual proof numbers are identical to real proof numbers. However, once we assign a thread to search a given node, we update its virtual proof numbers: we set `(ϕ_virt, δ_virt)` to `(0, ∞)` if If `ϕ < δ`, and to `(∞, 0)` otherwise. We then backpropagate those virtual proof numbers to the node's parents, and, if we have additional available threads, select a new most-proving node based on the new virtual proof numbers.

In essence, while we are searching a node, we provisionally assume that it will be solved by the search, and then find the new most-proving node(s) under that assumption, to search in parallel.

## Two-level search tree

My solver, similarly to SPDFPN, uses a two-layer search tree.

In the first layer, near the root of the search tree, we search in serial using virtual proof numbers in order to find (virtual) MPNs to dispatch to threads. Once we select an MPN, we send it to a thread to be searched in parallel with other nodes. That thread will search it -- up to some specified work budget -- using a vanilla serial DFPN search with a shared transposition table. Meanwhile, the serial root node will assign the node virtual PNs as described above, and select new MPNs to dispatch to available threads.

How does the first-level search decide whether to descend into a node's children itself, or to stop at a node and dispatch that node for parallel searching? Here we use the "work" notion defined above: we track the total amount of work that has been performed on a given node, and expand a node into its children (in the top-level tree) once a node has exceeded a threshold amount of work.

This heuristic works because "work performed so far" serves as an acceptably-good estime for "work that will be performed in the future," and balances the desire to split nodes early -- so we have more available parallelism -- with the desire to defer splitting nodes until we are sure there is enough work in that subtree to be worth multiple cores.

# Putting it together

In my PN-DFPN search, I use a classic reified proof number search for the first-layer tree near the root, with nodes augmented with virtual proof numbers. I use a worker pool model, wherein a single thread walks the top-level proof number tree, finds MPNs, and dispatches them to workers via a queue. Workers continually wait on their work queues for nodes to search, perform DFPN searches on those nodes up to a fixed work budget, and then return the resulting node -- along with one level of children -- via a separate queue.

When the root thread receives a completed job via a queue, it updates its own tree with the new proof numebrs, and resets the virtual proof numbers to match the real proof numbers. In addition, if the total work on the node exceeds the "split threshold" of work, it expands the node in its first-layer tree, adding the children returned by the worker thread, so that future searches will search those children in parallel.

You can find the full details [in my source code][source], which implements everything described here.

[source]: https://github.com/nelhage/ultimattt/blob/master/src/lib/prove/pn_dfpn.rs


## Compared to SPDFPN

My PN-DFPN has two primary differences compared to SPDFPN:

### First-level proof tree

Pawlewicz uses DFPN for both layers of his search tree, sharing the transposition table, and storing virtual proof numbers in a lookaside overlay data structure.

However, both SPDFPN and PN-DFPN must repeatedly return to the root of the top-level tree, in order to select new MPNs as threads complete and update children scattered throughout the tree. As [discussed in my DFPN presentation][dfpn-progres], DFPN relies on staying deep in the tree in order to guarantee progress; when I implemented the SPDFPN approach, I found my solver very frequently stopped making progress because the table was dropping key writes, and so the algorithm would continually return to the same MPN and be unable to store the result.

I do not have a detailed analysis of why SPDFPN did not work in my domain but did for Hex, but I suspect that the deep-and-narrow trees of Ultimate Tic Tac Toe -- and thus, the number of branching decisions required to reach an MPN -- is involved.

Secondly, Pawlewicz uses a global mutex to protect the top-level virtual search tree, and has each thread independently grab the mutex and search the tree when it wakes up. I opted for the queues-and-worker-pool model instead because I found it made the resulting concurrency much easier to reason about it.

## Concurrent transposition table

Pawlewicz's SPDFPN uses a shared transposition table with a single global reader-writer lock to manage concurrent accesses between threads. I found this gained insufficient parallelism and contention on that lock limited the avalable parallelism of my solver, so I implemented a finer-grained concurrency system, which I explore [in the next article][tt].

[pns]: /docs/ultimate/pn-search/
[spdfpn]: http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.353.270
[hex]: https://en.wikipedia.org/wiki/Hex_(board_game)
[mid]: docs/ultimate/pn-search/dfpn/#pseudo-code
[dfpn-progress]: /docs/ultimate/pn-search/dfpn/#a-note-on-this-presentation
[tt]: tt/
