# swift-cache

Use this package when many tasks may ask for the same expensive async value by key and it should be computed once, then kept: start from `Cache<Key, Value>`. When you only need a synchronous, thread-safe key-value store that holds a fixed number of entries, use `Cache<Key, Value>.Bounded` instead.

## Laws

- One computation per key at a time. The first caller of `value(for:compute:)` for a key runs its `compute`; callers arriving while it runs wait for that result and their own `compute` is never called.
- A successful value is kept until it is removed or replaced. `Cache<Key, Value>` has no capacity, expiry or eviction of its own.
- A failed computation is not kept. Its entry is removed, the computing caller and every waiter throw `Cache<Key, Value>.Error.computeFailed` with the error `compute` threw, and the next request computes again.
- A waiter that is cancelled throws `Cache<Key, Value>.Error.cancelled` promptly. The computation keeps running for the other callers.
- `compute` runs in the first caller's task, so cancelling that caller reaches `compute`. If `compute` then throws `CancellationError`, the computing caller throws `.computeFailed` and the waiters throw `.cancelled`.
- `removeValue(for:)` and `removeAll()` during a computation make its waiters throw `.cancelled`. The computation still finishes and returns its value to its own caller, but that value is not stored, and the next request starts a new computation.
- `setValue(_:for:)` during a computation gives the set value to the waiters and keeps it. The computing caller still receives its own result, which is not stored.
- `removeValue(for:when:)` only considers a stored value, never a computation in flight. The condition runs outside the lock, so it may read the same cache, and the value is removed only if the same entry is still stored afterwards.
- `cachedValue(for:)` and `contains(key:)` see stored values only. `count` and `isEmpty` also count computations in flight.
- `value(for:if:compute:)` with `false` returns a stored value or `nil`; it never joins a computation in flight.
- `Cache<Key, Value>.Bounded` evicts in first-in, first-out order once a new key would exceed `capacity`. Reading a key or replacing its value does not move it in that order. `removeValue(forKey:)` frees a slot, and `filter(_:)` keeps the order of the entries it retains. `Cache<Key, Value>.Bounded(capacity:)` traps unless `capacity` is positive. `filter(_:)` runs its closure under the lock, so the closure must not use the same cache.
- With the `Effect` trait, `Cache<Key, Value>.Compute<E>` and `Cache<Key, Value>.Evict` only describe a computation and an eviction. Neither `Cache<Key, Value>` nor `Cache<Key, Value>.Bounded` performs them.
