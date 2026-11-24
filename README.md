# swift-cache

Use this package when many tasks may ask for the same expensive async value by key and it should be computed once, then kept: start from `Cache<Key, Value>`. When you only need a synchronous, thread-safe key-value store that holds a fixed number of entries, use `Cache<Key, Value>.Bounded` instead. When one owner (an actor, or a task walking frames in order) keeps values between uses and should forget what goes unused, use `Cache<Key, Value>.Spans`: a plain value with no lock.

## Laws

- One computation per key at a time. The first caller of `value(for:compute:)` for a key runs its `compute`; callers arriving while it runs wait for that result and their own `compute` is never called.
- A successful value is kept until it is removed or replaced. `Cache<Key, Value>` has no capacity, expiry or eviction of its own.
- A failed computation is not kept. Its entry is removed, the computing caller and every waiter throw `Cache<Key, Value>.Error.computeFailed` with the error `compute` threw, and the next request computes again.
- A waiter that is cancelled throws `Cache<Key, Value>.Error.cancelled` promptly. The computation keeps running for the other callers.
- `compute` runs in the first caller's task, so cancelling that caller reaches `compute`. If `compute` then throws `CancellationError`, the computing caller and every waiter throw `.cancelled`, and the entry is removed as for any failure.
- `removeValue(for:)` and `removeAll()` during a computation make its waiters throw `.cancelled`. The computation still finishes and returns its value to its own caller, but that value is not stored, and the next request starts a new computation.
- `setValue(_:for:)` during a computation gives the set value to the waiters and keeps it. The computing caller still receives its own result, which is not stored.
- `removeValue(for:when:)` only considers a stored value, never a computation in flight. The condition runs outside the lock, so it may read the same cache, and the value is removed only if the same entry is still stored afterwards.
- `cachedValue(for:)` and `contains(key:)` see stored values only. `count` and `isEmpty` also count computations in flight.
- `value(for:if:compute:)` with `false` returns a stored value or `nil`; it never joins a computation in flight.
- `Cache<Key, Value>.Bounded` evicts in first-in, first-out order once a new key would exceed `capacity`. Reading a key or replacing its value does not move it in that order. `removeValue(forKey:)` frees a slot, and `filter(_:)` keeps the order of the entries it retains. `Cache<Key, Value>.Bounded(capacity:)` traps unless `capacity` is positive. `filter(_:)` runs its closure under the lock, so the closure must not use the same cache.
- `Cache<Key, Value>.Spans` holds the entries of this span and of the one before. `value(for:)` of an entry of the span before carries it into this one, without starting a span. `keep(_:for:)` of a key this span holds replaces it in place; of a new key once this span holds `capacity` entries, it first lets the span before go and starts a new one. So an entry survives exactly as long as it is used at least once a span. `contains(_:)` is not a use. `Cache<Key, Value>.Spans(capacity:)` traps unless `capacity` is positive.
- With the `Effect` trait, `Cache<Key, Value>.Compute<E>` and `Cache<Key, Value>.Evict` only describe a computation and an eviction. Neither `Cache<Key, Value>` nor `Cache<Key, Value>.Bounded` performs them.
