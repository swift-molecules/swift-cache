public import Cardinal
public import Hash_Table_Primitive
public import Synchronization

extension Cache {
    /// What was made from inputs, found again by them: a key's value is made once and handed back to whoever asks
    /// with an equal key, until it is forgotten by use. A value may depend on more than its key; it then says
    /// itself whether it holds, and a key keeps a few values, the latest first, each with the answers it was made
    /// under. A lookup never depends on the lookup before, so work done out of order and side by side shares one
    /// table.
    ///
    /// Two that ask for one key under equal conditions at once make one value: the second waits for the first.
    /// `Traces` is a reference; every copy of it is the same table.
    public final class Traces<Condition: Hashable & Sendable>: Sendable {
        @usableFromInline
        let shards: [Shard]

        /// How many values a key keeps.
        public let variants: Cardinal

        /// A table that keeps `capacity` keys in a span, as `Cache.Spans` does, and `variants` values of each.
        /// Traps unless both are positive.
        @inlinable
        public init(capacity: Cardinal, variants: Cardinal = .one) {
            precondition(capacity > .zero && variants > .zero, "Cache.Traces capacity and variants must be positive")
            let share = Swift.max(Int(clamping: capacity) / Self.count, 1)
            self.variants = variants
            self.shards = (0..<Self.count).map { _ in Shard(capacity: Cardinal(UInt(share))) }
        }
    }
}

extension Cache.Traces {
    /// How many shards the keys are split over, each under a lock of its own.
    @inlinable
    static var count: Int { 16 }

    /// A value a key keeps, and its number: no other value this table kept has it.
    public struct Kept: Sendable {
        public let value: Value
        public let number: Int

        @usableFromInline
        init(value: Value, number: Int) {
            self.value = value
            self.number = number
        }
    }

    /// What a lookup gives: the value, its number, and whether it was found rather than made.
    public struct Found: Sendable {
        public let value: Value
        public let number: Int?
        public let found: Bool

        @usableFromInline
        init(value: Value, number: Int?, found: Bool) {
            self.value = value
            self.number = number
            self.found = found
        }
    }

    /// How often a value was found, how often one was made, and how many keys were forgotten.
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

    /// What a value in the making is found by.
    @usableFromInline
    struct Making: Hashable, Sendable {
        @usableFromInline
        let key: Hash.Once<Key>
        @usableFromInline
        let condition: Condition

        @usableFromInline
        init(key: Hash.Once<Key>, condition: Condition) {
            self.key = key
            self.condition = condition
        }
    }

    /// A value in the making: whoever makes it holds the gate, and the others wait at it.
    @usableFromInline
    final class Gate: Sendable {
        @usableFromInline
        let mutex = Mutex<Void>(())

        @usableFromInline
        init() {}
    }

    @usableFromInline
    struct State: Sendable {
        @usableFromInline
        var spans: __CacheSpans<Hash.Once<Key>, [Kept]>
        @usableFromInline
        var making: [Making: Gate] = [:]
        @usableFromInline
        var counted = Count()
        @usableFromInline
        var next = 0

        @usableFromInline
        init(capacity: Cardinal) {
            self.spans = __CacheSpans(capacity: capacity)
        }
    }

    @usableFromInline
    final class Shard: Sendable {
        @usableFromInline
        let state: Mutex<State>

        @usableFromInline
        init(capacity: Cardinal) {
            self.state = Mutex(State(capacity: capacity))
        }
    }
}

extension Cache.Traces {
    /// The value of `key` that `holds`, found or made now. A value made now is kept where `keeps` it. Of those
    /// that ask under one `condition` at once, one makes the value and the others wait for it; `make` must not ask
    /// this table for the same key under the same condition.
    @inlinable
    public func value<E: Swift.Error>(
        for key: Key,
        under condition: Condition,
        where holds: (Value) -> Bool,
        keeps: (Value) -> Bool = { _ in true },
        make: () throws(E) -> Value
    ) throws(E) -> Found {
        let key = Hash.Once(key)
        let place = Int(UInt(bitPattern: key.hash) % UInt(shards.count))
        let shard = shards[place]
        if let found = Self.found(key, in: shard, where: holds) { return found }
        let making = Making(key: key, condition: condition)
        while true {
            let mine = Gate()
            let turn = try mine.mutex.withLock { _ throws(E) -> Turn in
                let other = shard.state.withLock { state -> Gate? in
                    if let gate = state.making[making] { return gate }
                    state.making[making] = mine
                    return nil
                }
                if let other { return .wait(other) }
                defer { shard.state.withLock { $0.making[making] = nil } }
                if let found = Self.found(key, in: shard, where: holds) { return .done(found) }
                let value = try make()
                return .done(keep(value, for: key, at: place, kept: keeps(value)))
            }
            switch turn {
            case .done(let found):
                return found

            case .wait(let other):
                other.mutex.withLock { _ in }
                if let found = Self.found(key, in: shard, where: holds) { return found }
            }
        }
    }

    /// What one turn at a value in the making comes to: the value, or another to wait for.
    @usableFromInline
    enum Turn: Sendable {
        case done(Found)
        case wait(Gate)
    }

    @inlinable
    static func found(_ key: Hash.Once<Key>, in shard: Shard, where holds: (Value) -> Bool) -> Found? {
        let kept = shard.state.withLock { $0.spans.value(for: key) }
        guard let kept, let found = kept.first(where: { holds($0.value) }) else { return nil }
        shard.state.withLock { $0.counted.found += 1 }
        return Found(value: found.value, number: found.number, found: true)
    }

    @inlinable
    func keep(_ value: Value, for key: Hash.Once<Key>, at place: Int, kept: Bool) -> Found {
        let variants = Int(clamping: variants)
        let count = shards.count
        let number = shards[place].state.withLock { state -> Int? in
            state.counted.made += 1
            guard kept else { return nil }
            let number = state.next &* count &+ place
            state.next += 1
            var list = state.spans.value(for: key) ?? []
            list.insert(Kept(value: value, number: number), at: 0)
            if list.count > variants { list.removeLast() }
            state.counted.forgotten += state.spans.keep(list, for: key).count
            return number
        }
        return Found(value: value, number: number, found: false)
    }

    /// The table's counts so far, over every shard.
    public var counted: Count {
        shards.reduce(into: Count()) { counted, shard in
            let part = shard.state.withLock { $0.counted }
            counted.found += part.found
            counted.made += part.made
            counted.forgotten += part.forgotten
        }
    }
}

extension Cache.Traces where Condition == Bool {
    /// The value of a key that decides it alone, found or made now.
    @inlinable
    public func value<E: Swift.Error>(for key: Key, make: () throws(E) -> Value) throws(E) -> Found {
        try value(for: key, under: true, where: { _ in true }, make: make)
    }
}
