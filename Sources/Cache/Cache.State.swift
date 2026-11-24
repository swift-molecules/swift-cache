extension Cache {

    /// What the lock protects. An entry's number is its own: a key removed and asked for again has another.
    @usableFromInline
    struct State {
        @usableFromInline
        var entries: [Key: Entry] = [:]

        @usableFromInline
        var next: UInt64 = 0

        @inlinable
        package init() {}
    }
}

extension Cache.State {
    /// Enters a key whose value is being computed, and gives its number.
    @inlinable
    mutating func begin(_ key: Key) -> UInt64 {
        enter(.computing(Cache.Entry.Waiters()), for: key)
    }

    /// Keeps a key's value, under a number of its own.
    @inlinable
    mutating func keep(_ value: Value, for key: Key) {
        _ = enter(.ready(value), for: key)
    }

    @inlinable
    mutating func enter(_ entry: Cache.Entry.State, for key: Key) -> UInt64 {
        defer { next &+= 1 }
        entries[key] = Cache.Entry(number: next, state: entry)
        return next
    }
}
