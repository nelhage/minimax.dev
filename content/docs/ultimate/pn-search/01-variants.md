---
weight: 1
slug: variants
title: "Variants and refinements"
---

# Proof Number search: variants and refinements

Having presented basic Proof Number search, I will present some observations, optimizations, and refinements, focusing primarily on ones that I have used in my Ultimate Tic Tac Toe solver.

The work in this section is a mix of summaries from [Kishimoto et al](first-20-years) and optimizations I happened upon during my project. I will attempt to flag which is which.

## φ-δ search

An implementation of vanillya PN search ends up containing two sets of (d)pn-calculation and MPN-selection routines, one for AND nodes and one for OR nodes, which are essentially identical except for swapping the roles of `pn` and `dpn`. In the style of [negamax][negamax], we can restore equivalence between the cases by replacing `pn` and `dpn` with φ and δ, which store proof numbers from the perspective of the player to play in a given node, instead of from the perspective of the top-level node. Specifically, we define

{{<katex display>}}
\begin{aligned}
\phi(N) &= \begin{cases}
pn(N) & \text{if $N$ is an OR node} \\
dpn(N) & \text{if $N$ is an AND node}
\end{cases}
\\
\delta(N) &= \begin{cases}
dpn(N) & \text{if $N$ is an OR node} \\
pn(N) & \text{if $N$ is an AND node}
\end{cases}

\end{aligned}
{{</katex>}}

We can then consistently update φ and δ by the single rule:

{{<katex>}}
\begin{aligned}
\phi(N)  &= \min_{c\in \operatorname{succ}(N)}\delta(c) \\
\delta(N) &= \sum_{c\in \operatorname{succ}(N)}\phi(c)
\end{aligned}
{{</katex>}}

And select an MPN as the child with minimal δ.

Kishimoto et al (and other sources) present φ-δ in order to simplify the description of DFPN search (which I will introduce later), but it works just as well for vanilla PN search.

One small gotcha when implementing φ-δ search is that the [handling of draws][draw] introduced previously introduces a slight asymmetry in the handling of terminal nodes. Specifically, we must be careful to always assign draws as wins for the top-level defender, regardless of which player makes the move that leads to the final draw.

## Staying deep in the tree

In a vanilla PN implementation as described, after expanding a node, we return to the root of the search tree, updating proof numbers as we go, and then repeat the MPN selection routine from the root.

[Allis][searching-for-solutions] was the first to make the observation that we don't need to return all the way to the root; if, during backpropagation, we encounter a node whose proof numbers do not change as a result of our update, we know that no other proof numbers will change, and additionally that the MPN is still in this subtree, and so we can immediately stop propagation and search for a new MPN in this subtree.

It was later noted that you can go further -- if a node's (d)pn changes, but that node still has δ ≤ its parent's φ, then we know the MPN remains in this subtree and we can stop and resume searching. This shortcut may leave the proof numbers higher in the tree temporarily out-of-date, but will still expand the same sequence of leaf nodes as vanilla PN, for less total work.

Further following this line of thought will be a key step towards depth-first proof number search (DFPN).

# Memory usage

The greatest limitation of PN search is shared by most best-first or breadth-first search algorithms: because PN search reifies the entire tree being searched, it is memory-hungry and cannot search trees larger than can fit in memory.

In this section, we will explore some optimizations that can incrementally improve memory usage, and then next time we'll describe depth-first proof number search, which converts PN search to a depth-first algorithm which can operate in constant memory (albeit with the cost of additional computational work).

## Freeing subtrees

(This section is all taken from Kishimoto et al and their various citations)

Once a node has been solved (`pn=0` or `dpn=0`), we will never need to visit it again, and so we can free its children (and the entire subtrees rooted at them). This can slow growth of the search tree somewhat, but tends to gain only a small constant factor in general; As a best-first algorithm, PN search tries to avoid proving unnecessary nodes as much as possible, which also prevents us from freeing them.

We can also heuristically free trees that are "unpromising," by e.g eliminating children with the _maximal_ δ as unlikely to feature in the proof. These heuristics risk rendering the solver unsound, however.

## PN² search

PN² (also proposed by [Allis][searching-for-solutions]) aims to allow PN search to search trees potentially much larger than memory. The core idea of PN² is to augment the "expansion" routine of PN search. When we expand an MPN, instead of merely expanding its children, we perform a _second_ layer of PN search rooted from the MPN, up to some budget of tree size. When we solve the node or exceed our tree size budget, we discard the entire tree, keeping only the direct children of the former MPN.

If PN search is capable of searching a tree of size _M_, PN² should be capable of searching a tree of size something like {{<katex>}}\left(\frac{k\cdot{}M}{2}\right)^2{{</katex>}} -- we allocate half of memory to each layer of the tree, and for each of the {{<katex>}}\frac{k\cdot{}M}{2}{{</katex>}} leaves of the first-level tree, we can search a further {{<katex>}}\frac{M}{2}{{</katex>}} nodes. For a large tree of branching factor > 1, most of the nodes will be leaf nodes, and so we will have k nearly equal to 1.

PN² suffers from at least two major weaknesses:

- It repeats a lot of work, because it repeatedly performs a PN search at the leaves and then discards nearly all of the work except for the first layer.
- PN² breaks the best-first property of the search. When we visit an MPN, we perform a search up to some memory budget, even after the node is no longer an MPN. This can further waste work examining subtrees which turn out to be irrelevant.

A key challenge in PN² is choosing how to set the memory budget for the second-level search. Setting a larger budget allows PN² to search larger trees, but it exacerbates both of the problems above. Practical implementations of PN² tend to perform some sort of annealing of the budget from near 1 (which reproduces vanilla PN search) at the start of the search, up to "the size of the first-level tree" as the tree grows.

## Efficient tree representations

(This section is largely my own work based on implementing various PN search algorithms. I'm sure some of these optimizations are covered in the literature but I haven't seen many references to the practicalities of an efficient representation)

If PN search is limited by the size of our tree, how efficiently can we represent each node in memory in order to fit a larger tree in a given amount of RAM?

The most straightforward representation of a node might look something like this:

```cpp
struct Node {
  uint32_t phi;
  uint32_t delta;
  Node *parent;
  // `nullptr_t` if this is node is a leaf node
  // A leaf node with phi != 0 && delta != 0 is unexpanded
  unique_ptr<vector<Node*>> children;
  Position pos;
};
```

Assuming a 64-bit machine, we store `8` bytes for φ and δ, and another `8` each for the parent pointer and the pointer to children. In addition, each node costs the `8` byte pointer to it stored in its parent's `children`. So we arrive at 32 bytes plus `sizeof(Position)`, which is 40 bytes in my implementation, for a total of 72 bytes per node.

However, it turns out there are numerous optimizations available to us:

First, we can replace the 8-byte `Node *` with a 4-byte (32-bit) `NodeRef` by packing our nodes into a flat array. We can do this in several ways, perhaps most simply by `mmap`ing a region of size `2³² * sizeof(Node)` and populating it with physical memory as needed. This will require less than a terabyte of virtual address space, which is readily available on a 64-bit machine. This is similar to the [*Ref][sorbet-ref] trick I described Sorbet using.

The largest win comes from removing the `Position` field, and replace it with the **move** that we made to reach this position from its parent. We only need the position at leaf nodes (to expand their children), and we only ever reach leaves by walking down from the root. As long as we separately store the `Position` corresponding to the root, we can reconstruct positions as we go by simply playing the `move` from each node as we descend. In order to support moving both up and down the tree (as is needed if we implement the optimizations to stay deep in the tree described above), we can store a full stack holding the path from the root to current node, and pop off that stack to go up a level.

This optimization appears at first to be a time-space tradeoff; we're making our tree structure in exchange for spending more CPU time replaying moves. However, in my experiments, I found that removing positions from the tree actually _speeds up the solver_, I suspect by making CPU caches more effective at caching the tree!

As long as we're maintaining a stack containing the path-to-root, we no longer need the `parent` pointer, either -- instead of chasing a node's parent, we can store that parent's ID in the stack and instead pop off the stack to go up a level in the tree.

Finally, we'll replace the `vector<Node*>` children with a pair of `first_child` and `sibling` pointers, representing children as a linked list. Since `NodeID`s are 4 byte, two IDs is the same size as the `unique_ptr` used previously, and also removes the need to store the `vector` itself in additional memory. This layout also has the advantage of removing any reliance on the system allocator, giving us very predictable memory usage and memory layout.

In this case we do have a genuine time/space tradeoff: switching to a linked list does have negative performance impact, since chasing linked lists is bad for cache performance relative to walking an array of pointers.

After all of these optimizations, we arrive at a `Node` structure looking something like:

```cpp
struct Node {          // size / running total
  uint32_t phi;        // 4    / 4
  uint32_t delta;      // 4    / 8
  NodeID first_child;  // 4    / 12
  NodeID next_sibling; // 4    / 16
  uint16_t flags;      // 2    / 18
  Move move;           // 1    / 19
  uint8_t _pad;        // 1    / 20
};
```

`Move` is 1 byte in my Ultimate Tic Tac Toe implementation; other games might require larger size. In order to ensure proper alignment the compiler will pad the struct to a multiple of 4 bytes, so we use 2 of them to add a 16-bit flag word, which we can use to track metadata such as "is this an AND or OR node" and whether a node has been expanded.

20 bytes, nearly a 4x reduction from our initial 72 bytes! Since we are limited to 4B nodes by our 32-bit node IDs, this representation is only capable of making use of up to 80GiB of memory. My development desktop only has 32GiB of RAM as of this writing so that's not been a problem for me, but we can use other approaches to make use of larger memory sizes.


[first-20-years]: https://webdocs.cs.ualberta.ca/~mmueller/ps/ICGA2012PNS.pdf
[negamax]: (https://en.wikipedia.org/wiki/Negamax
[draw]: /docs/ultimate/pn-search/#win-or-lose-there-is-no-draw
[searching-for-solutions]: https://project.dke.maastrichtuniversity.nl/games/files/phd/SearchingForSolutions.pdf
[sorbet-ref]: https://blog.nelhage.com/post/why-sorbet-is-fast/#globalstate-and-ref
