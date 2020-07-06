---
slug: tt
title: The transposition table
---

As discussed [in the section on DFPN][dfpn], DFPN is reliant on a [transposition table][tt] to store the results of proof number searches to date, in order to reuse work across searches on the same nodes.

My transposition table for Ultimate Tic Tac Toe uses a number of fairly straightforward techniques borrowed from chess programming and prior solvers.

I store a linear array of `Entry` buckets, which contain the [zobrist hash][zobrist] of positions, as well as the `(ϕ, δ)` bounds and a few additional statistics about each node. As is usual practice in transposition tables, I do not store the entire position, but only the zobrist hash. This does admit the possibility of collisions between nodes in the search, but saves a lot of memory and seems to be standard practice even for solvers.

I use a linear-probe strategy with a fixed four bucket probe window. That is, on lookup, I examine the buckets at index `H % N`, `(H+1) % N`, ``(H+2) % N`, and `(H+3) % N`, where `H` is the position's hash value, and `N` is the number of buckets, and return if any bucket matches the hash. On write to the table, I examine the same set of buckets, and pick one to overwrite:
- If one of them matches the hash value to be written, we overwrite that bucket with the new result
- Otherwise, we pick the one with the least [`work`][work] performed so far. This ensures that we preserve the entries on which we have spent the most computation so far.

If the entry-to-be-written has less work than the minimal-work bucket, we have the choice of whether to overwrite and discard the old element, or to discard the new element. I have experimented with both policies and not found a substantial difference. My current table opts to overwrite, ensuring that the table continues to reflect recent work.

## The index array

For large searches, I use hash tables consuming 10GiB of memory or more. Such a table is much larger than the L2 or even L3 cache, and is accessed in a very random-access fashion, meaning that we're essentially bottlenecked on the (comparatively slow) latency to main memory.

Borrowing a trick from [Google's "Swiss tables"][swisstable], I have augmented my hash table with an additional array which stores, for each entry in the table, a single byte of the hash value at that position. On lookup, we first check this "index" array, and, if the low bytes don't match, we can avoid going to the main entry entirely.

This index is still too large to fit entirely in L3 cache, but we can fit a much higher fraction of it, and in my experiments it is a performance win, even taking into account the fact that means we store ~3% fewer table entries in the same amount of memory.

## Concurrency

In [PN-DFPN][pn-dfpn], multiple threads search the table concurrently, both reading and writing. In order to achieve good parallelism, we need them to be able to efficiently access the table concurrently.

To support this concurency, I have dedicated 32 bits of each entry to synchronization (as it happens, my table entries otherwise had 32 bits of padding due to alignment concerns, so this is essentially "free" in terms of memory usage).

These 32 bits are used to implement a combined [seqlock][seqlock] and mutex.

I use the low 2 bits to implement a mutex on top of Rust's [`parking_lot_core`][parking_lot_core] crate, which uses a separate "parking lot" to handle thread suspending and queueing to support very compact and efficient locks. This mutex is used by writers to the table, which acquire the lock on an element before writing to it.

The high 30 bits are used as a [seqlock][seqlock]. Essentially, writers increment the sequence counter before beginning and after concluding a write; readers, in turn, read the counter before and after reading an element from the table; if they find that the counter has not changed, they can be confident they did not race with any writer and read a consistent view of the element. This allows for very efficient reads, especially in the uncontended case.

## Source

You can read the [source code][source] for my transposition table on github.


[seqlock]: https://en.wikipedia.org/wiki/Seqlock
[parking_lot_core]: https://docs.rs/parking_lot_core/0.8.0/parking_lot_core/index.html
[dfpn]: /docs/ultimate/pn-search/dfpn/#a-note-on-this-presentation#transposition-tables
[tt]: https://www.chessprogramming.org/Transposition_Table
[zobrist]: /docs/ultimate/efficient-representation/hashing/
[work]: /docs/ultimate/pn-dfpn/#work-budgets
[swisstable]: https://abseil.io/docs/cpp/guides/container#hash-tables
[pn-dfpn]: /docs/ultimate/pn-dfpn/
[source]: https://github.com/nelhage/ultimattt/blob/master/src/lib/table.rs
