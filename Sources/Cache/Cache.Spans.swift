extension Cache {

    /// A cache that is a plain value and forgets by use: it holds the entries of this span and of the one before.
    /// Reading an entry of the span before carries it into this one. Once this span holds `capacity` entries, the
    /// next new key starts a new span and the span before is let go, so whatever was not read for a whole span is
    /// forgotten. Carrying an entry over never starts a span, so this span may briefly hold more than `capacity`.
    /// It has no lock: whoever holds the value owns it.
    public struct Spans {
        @usableFromInline
        var current: [Key: Value] = [:]

        @usableFromInline
        var previous: [Key: Value] = [:]

        /// How many entries a span holds before the next new key starts another.
        public let capacity: Int

        /// A cache whose spans each hold `capacity` entries. Traps unless `capacity` is positive.
        @inlinable
        public init(capacity: Int) {
            precondition(capacity > 0, "Cache.Spans capacity must be positive")
            self.capacity = capacity
        }
    }
}

extension Cache.Spans {

    /// The value kept for `key`, which is thereby used in this span; `nil` when neither span holds it.
    @inlinable
    public mutating func value(for key: Key) -> Value? {
        if let found = current[key] { return found }
        guard let found = previous[key] else { return nil }
        current[key] = found
        return found
    }

    /// Keeps `value` for `key` in this span. A key this span already holds is replaced in place; a new key into a
    /// full span starts a new span first.
    @inlinable
    public mutating func keep(_ value: Value, for key: Key) {
        if current[key] == nil, current.count >= capacity {
            previous = current
            current = [:]
        }
        current[key] = value
    }

    /// The value kept for `key`, made by `make` and kept when neither span holds it.
    @inlinable
    public mutating func value<E: Swift.Error>(for key: Key, make: () throws(E) -> Value) throws(E) -> Value {
        if let found = value(for: key) { return found }
        let made = try make()
        keep(made, for: key)
        return made
    }

    /// Whether either span holds `key`. Unlike `value(for:)`, this does not count as a use.
    @inlinable
    public func contains(_ key: Key) -> Bool {
        current[key] != nil || previous[key] != nil
    }

    /// The number of entries both spans hold.
    @inlinable
    public var count: Int {
        current.count + previous.keys.count { current[$0] == nil }
    }

    /// Forgets every entry.
    @inlinable
    public mutating func removeAll() {
        current = [:]
        previous = [:]
    }
}

extension Cache.Spans: Equatable where Value: Equatable {}
