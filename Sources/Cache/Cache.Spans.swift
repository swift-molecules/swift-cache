public import Cardinal

/// A cache that is a plain value and forgets by use: it holds the entries of this span and of the one before.
/// Reading an entry of the span before carries it into this one. Once this span holds `capacity`, the next new
/// key starts a new span and the span before is let go, so whatever was not read for a whole span is forgotten.
/// Carrying an entry over never starts a span, so this span may briefly hold more than `capacity`. An entry
/// counts for one unless it is kept at a cost of its own, such as its bytes. It has no lock: whoever holds the
/// value owns it, and it is `Sendable` exactly when its keys and values are.
///
/// It is spelled `Cache<Key, Value>.Spans` where the keys and values are `Sendable`, as `Cache` asks of its
/// own, and by this name where they are not.
public struct __CacheSpans<Key: Hashable, Value> {
    @usableFromInline
    var current: [Key: (value: Value, cost: Int)] = [:]

    @usableFromInline
    var previous: [Key: (value: Value, cost: Int)] = [:]

    /// What this span holds: the costs of its entries, added up.
    @usableFromInline
    var filled = 0

    /// How much a span holds before the next new key starts another.
    public let capacity: Cardinal

    /// A cache whose spans each hold `capacity`. Traps unless `capacity` is positive.
    @inlinable
    public init(capacity: Cardinal) {
        precondition(capacity > .zero, "Cache.Spans capacity must be positive")
        self.capacity = capacity
    }
}

extension Cache {
    /// `__CacheSpans` of this cache's keys and values.
    public typealias Spans = __CacheSpans<Key, Value>
}

extension __CacheSpans {
    /// The value kept under a key, in this span or the one before; one of the span before is carried into this
    /// span, with its cost.
    @inlinable
    public mutating func value(for key: Key) -> Value? {
        if let found = current[key] { return found.value }
        guard let found = previous[key] else { return nil }
        current[key] = found
        filled += found.cost
        return found.value
    }

    /// Keeps a value under a key at a cost, one unless said. A key this span holds is replaced in place. A new
    /// key, once this span holds `capacity`, first starts a new span: the span before is let go and given back,
    /// for an owner that must take care of what it held; otherwise nothing is given.
    @inlinable
    @discardableResult
    public mutating func keep(_ value: Value, for key: Key, cost: Cardinal = .one) -> [Key: Value] {
        let cost = Int(clamping: cost)
        var released: [Key: Value] = [:]
        if let held = current[key] {
            filled -= held.cost
        } else if filled >= Int(clamping: capacity) {
            for (old, entry) in previous where current[old] == nil { released[old] = entry.value }
            previous = current
            current = [:]
            filled = 0
        }
        current[key] = (value, cost)
        filled += cost
        return released
    }

    /// The value kept under a key, or made now and kept.
    @inlinable
    public mutating func value<E: Swift.Error>(for key: Key, make: () throws(E) -> Value) throws(E) -> Value {
        if let found = value(for: key) { return found }
        let made = try make()
        keep(made, for: key)
        return made
    }

    /// Whether a value is kept under a key, in either span. It is not a use: nothing is carried over.
    @inlinable
    public func contains(_ key: Key) -> Bool {
        current[key] != nil || previous[key] != nil
    }

    /// How many entries are kept, in both spans.
    @inlinable
    public var count: Int {
        current.count + previous.keys.count { current[$0] == nil }
    }

    /// Lets go of everything.
    @inlinable
    public mutating func removeAll() {
        current = [:]
        previous = [:]
        filled = 0
    }
}

extension __CacheSpans: Equatable where Value: Equatable {
    @inlinable
    public static func == (first: Self, second: Self) -> Bool {
        first.capacity == second.capacity && first.filled == second.filled
            && Self.same(first.current, second.current) && Self.same(first.previous, second.previous)
    }

    @inlinable
    static func same(_ first: [Key: (value: Value, cost: Int)], _ second: [Key: (value: Value, cost: Int)]) -> Bool {
        guard first.count == second.count else { return false }
        for (key, entry) in first {
            guard let other = second[key], other.value == entry.value, other.cost == entry.cost else { return false }
        }
        return true
    }
}

extension __CacheSpans: Sendable where Key: Sendable, Value: Sendable {}
