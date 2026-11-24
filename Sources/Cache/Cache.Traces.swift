public import Cardinal
public import Hash_Table_Primitive

/// What was made from inputs, found again by them: a key's value is made once and handed back to whoever asks with
/// an equal key, until it is forgotten by use. A value may depend on more than its key; whoever asks then says which
/// holds, and a key keeps a few values, the latest first. A lookup never depends on the lookup before, so work done
/// out of order shares one table.
///
/// It is a plain value with no lock, as `Cache.Spans` is: whoever holds it owns it, and it is `Sendable` exactly when
/// its keys and values are. It is spelled `Cache<Key, Value>.Traces` where the keys and values are `Sendable`, and by
/// this name where they are not.
public struct __CacheTraces<Key: Hashable, Value> {
    @usableFromInline
    var spans: __CacheSpans<Hash.Once<Key>, [Kept]>

    @usableFromInline
    var next = 0

    /// How many values a key keeps.
    public let variants: Cardinal

    @usableFromInline
    var counts = Count()

    /// A table that keeps `capacity` keys in a span, as `Cache.Spans` does, and `variants` values of each. Traps
    /// unless both are positive.
    @inlinable
    public init(capacity: Cardinal, variants: Cardinal = .one) {
        precondition(variants > .zero, "Cache.Traces variants must be positive")
        self.variants = variants
        self.spans = __CacheSpans(capacity: capacity)
    }
}

extension Cache {
    /// `__CacheTraces` of this cache's keys and values.
    public typealias Traces = __CacheTraces<Key, Value>
}

extension __CacheTraces {
    /// A value a key keeps, and its number: no other value this table kept has it.
    public struct Kept {
        public let value: Value
        public let number: Int

        @inlinable
        init(value: Value, number: Int) {
            self.value = value
            self.number = number
        }
    }

    /// How often a value was found, how often one was kept, and how many keys were forgotten.
    public struct Count: Sendable, Hashable {
        public var found = 0
        public var made = 0
        public var forgotten = 0

        @inlinable
        public init(found: Int = 0, made: Int = 0, forgotten: Int = 0) {
            self.found = found
            self.made = made
            self.forgotten = forgotten
        }
    }
}

extension __CacheTraces {
    /// The latest value kept under a key that `holds`, or nil. It is a use of the key.
    @inlinable
    public mutating func found(_ key: Hash.Once<Key>, where holds: (Value) -> Bool = { _ in true }) -> Kept? {
        guard let found = spans.value(for: key)?.first(where: { holds($0.value) }) else { return nil }
        counts.found += 1
        return found
    }

    /// Keeps a value under a key as its latest, letting go of the oldest beyond `variants`.
    @inlinable
    @discardableResult
    public mutating func keep(_ value: Value, for key: Hash.Once<Key>) -> Kept {
        let kept = Kept(value: value, number: next)
        next += 1
        counts.made += 1
        var list = spans.value(for: key) ?? []
        list.insert(kept, at: 0)
        if list.count > Int(clamping: variants) { list.removeLast() }
        counts.forgotten += spans.keep(list, for: key).count
        return kept
    }

    /// The value of a key that decides it alone, found, or made now and kept.
    @inlinable
    public mutating func value<E: Swift.Error>(for key: Key, make: () throws(E) -> Value) throws(E) -> Kept {
        let key = Hash.Once(key)
        if let found = found(key) { return found }
        return keep(try make(), for: key)
    }
}

extension __CacheTraces {
    /// How often a value was found, how often one was kept, and how many keys were forgotten.
    @inlinable
    public var counted: Count { counts }
}

extension __CacheTraces: Sendable where Key: Sendable, Value: Sendable {}

extension __CacheTraces.Kept: Sendable where Key: Sendable, Value: Sendable {}
