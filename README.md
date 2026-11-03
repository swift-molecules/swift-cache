# swift-cache

Use `Cache` when an expensive async value is keyed and many tasks may ask for the same key at once: the first caller computes it, the others wait for that one computation, and later callers get the stored value. Use `Cache.Bounded` when you only need a thread-safe key-value store that holds at most a fixed number of entries.

## Model

- `Cache<Key, Value>` is a `Sendable` value with reference semantics: copies share one store, guarded by a lock.
- `value(for:compute:)` returns the stored value, joins a computation already running for that key, or starts one. Only the first caller's `compute` runs; every concurrent caller for that key receives its result.
- `setValue(_:for:)` stores a value directly and hands it to any callers waiting on that key.
- `removeValue(for:)` and `removeAll()` drop entries; callers waiting on a removed computation throw `Cache.Error.cancelled`. `removeValue(for:when:)` removes a stored value only if the condition holds for it.
- `cachedValue(for:)`, `contains(key:)`, `count` and `isEmpty` read without computing.
- `Cache.Bounded<Key, Value>` is a separate, synchronous store with a positive `capacity`: inserting a new key past capacity evicts the oldest inserted key (first in, first out; reads do not refresh order). Re-inserting an existing key replaces its value in place.

## Rules

- A failed computation is not cached. The entry is removed, every caller waiting on it receives the failure, and the next `value(for:compute:)` computes again.
- A caller that is cancelled while waiting throws `Cache.Error.cancelled`; the shared computation keeps running for the others.
- `compute` must be safe to run concurrently with computations for other keys; it never runs twice concurrently for one key.

## Error Handling

`value(for:compute:)` throws `Cache.Error`: `.computeFailed(error)` wraps what `compute` threw, and `.cancelled` reports a cancelled wait.

## Example

```swift
let profiles = Cache<User.ID, Profile>()

let profile = try await profiles.value(for: id) {
    try await api.profile(id)
}
```

## Effect

With the `Effect` trait, `Cache.Compute` and `Cache.Evict` describe a computation and an eviction (with its `Reason`: explicit, capacity limit, expired, replaced, cleared) as effects, so a caller can intercept or record them.
