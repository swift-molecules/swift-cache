public import Array
public import Array_Primitive
internal import Async
public import Async_Waiter
public import Buffer
public import Buffer_Linear_Primitive
public import Buffer_Ring_Primitive
public import Memory
public import Memory_Allocator
public import Memory_Allocator_Protocol
public import Lock
public import Queue
import Standard_Library_Extensions
public import Storage
import _Concurrency

public struct Cache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    @usableFromInline
    let _storage: Lock<State>

    #if DEBUG
        /// Called after a waiter has queued, for tests.
        let waiterEnqueued: Lock<Enqueued>

        public init() {
            self._storage = Lock(State())
            self.waiterEnqueued = Lock(Enqueued())
        }
    #else
        public init() {
            self._storage = Lock(State())
        }
    #endif
}

extension Cache {

    public typealias _Value = Value
}

extension Cache {

    public func value(
        for key: Key,

        compute: @Sendable () async throws -> Value
    ) async throws(Self.Error) -> Value {

        let action = _storage.withLock { state -> Action in
            guard let entry = state.entries[key] else {

                return .compute(state.begin(key))
            }
            switch entry.state {
            case .ready(let value):

                return .returnValue(value)

            case .computing:

                return .join(entry.number)
            }
        }

        switch action {
        case .returnValue(let value):
            return value

        case .join(let number):
            if let value = try await waitForValue(of: key, number) { return value }
            return try await value(for: key, compute: compute)

        case .compute(let number):
            return try await computeAndPublish(key: key, number, compute: compute)
        }
    }
}

extension Cache {

    /// The value being computed for a key under a number, or nil where that computation ended before this caller
    /// queued and left nothing to wait for.
    @usableFromInline
    func waitForValue(of key: Key, _ number: UInt64) async throws(Self.Error) -> Value? {
        let flag = Async.Waiter.Flag()

        let outcome: Entry.Waiters.Outcome?
        do {
            outcome = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Entry.Waiters.Outcome?, any Swift::Error>) in
                    let resumption = _storage.withLock { state -> Async.Waiter.Resumption? in
                        guard let entry = state.entries[key], entry.number == number else {

                            return Async.Waiter.Resumption {
                                continuation.resume(returning: nil)
                            }
                        }
                        switch entry.state {
                        case .ready(let value):

                            return Async.Waiter.Resumption {
                                continuation.resume(returning: Entry.Waiters.Outcome.success(value))
                            }

                        case .computing(let waiters):

                            if flag.cancelled {
                                return Async.Waiter.Resumption {
                                    continuation.resume(returning: Entry.Waiters.Outcome.failure(CancellationError()))
                                }
                            }

                            let asyncContinuation = Async.Continuation<Entry.Waiters.Outcome> {
                                outcome in
                                continuation.resume(returning: outcome)
                            }
                            let waiterEntry = Async.Waiter.Entry(
                                continuation: asyncContinuation,
                                flag: flag
                            )
                            waiters.queue.enqueue(waiterEntry)
                            return nil
                        }
                    }

                    if let resumption {
                        resumption.resume()
                    } else {
                        #if DEBUG
                            waiterEnqueued.withLock { $0.call }?()
                        #endif
                    }
                }
            } onCancel: {

                if flag.cancel() {
                    pumpCancelledWaiters(of: key, number)
                }
            }
        } catch {
            throw .cancelled
        }

        switch outcome {
        case nil:
            return nil

        case .success(let value):
            return value

        case .failure(let error):
            throw Error(failure: error)
        }
    }
}

extension Cache {

    @usableFromInline
    func pumpCancelledWaiters(of key: Key, _ number: UInt64) {
        var resumptions = __Array<Buffer<Storage::Storage<Memory.Allocator<Memory.Heap>>.Contiguous<Async.Waiter.Resumption>>.Linear>(initialCapacity: 0)
        _storage.withLock { state in
            guard let entry = state.entries[key], entry.number == number, case .computing(let waiters) = entry.state else {

                return
            }

            var flagged = Async.Waiter.Queue.Drain<
                Async.Waiter.Queue.Flagged<Entry.Waiters.Outcome, Void>
            >()
            waiters.queue.reapFlagged(into: &flagged)

            while let flaggedEntry = flagged.dequeue() {
                resumptions.append(
                    flaggedEntry.resumption { _ in .failure(CancellationError()) }
                )
            }
        }

        resumptions.drain { $0.resume() }
    }
}

extension Cache {

    @usableFromInline
    func computeAndPublish(
        key: Key,
        _ number: UInt64,

        compute: @Sendable () async throws -> Value
    ) async throws(Self.Error) -> Value {

        let result: Result<Value, any Swift::Error>

        do {
            let value = try await compute()
            result = .success(value)
        } catch {
            result = .failure(error)
        }

        var resumptions = __Array<Buffer<Storage::Storage<Memory.Allocator<Memory.Heap>>.Contiguous<Async.Waiter.Resumption>>.Linear>(initialCapacity: 0)
        _storage.withLock { state in
            guard let entry = state.entries[key], entry.number == number, case .computing(let waiters) = entry.state else {

                return
            }

            switch result {
            case .success(let value):
                state.entries[key] = Entry(number: number, state: .ready(value))

            case .failure:

                state.entries.removeValue(forKey: key)
            }

            waiters.queue.drain { waiterEntry in

                if waiterEntry.flag.cancelled {
                    resumptions.append(waiterEntry.resumption(with: .failure(CancellationError())))
                } else {
                    resumptions.append(waiterEntry.resumption(with: result))
                }
            }
        }

        resumptions.drain { $0.resume() }

        switch result {
        case .success(let value):
            return value

        case .failure(let error):
            throw Error(failure: error)
        }
    }
}

extension Cache {

    @inlinable
    public func cachedValue(for key: Key) -> Value? {
        _storage.withLock { state in
            guard let entry = state.entries[key] else {
                return nil
            }
            if case .ready(let value) = entry.state {
                return value
            }
            return nil
        }
    }

    @inlinable
    public func contains(key: Key) -> Bool {
        cachedValue(for: key) != nil
    }

    @inlinable
    public var count: Int {
        _storage.withLock { state in
            state.entries.count
        }
    }

    @inlinable
    public var isEmpty: Bool {
        _storage.withLock { state in
            state.entries.isEmpty
        }
    }
}

extension Cache {

    @inlinable
    public func setValue(_ value: Value, for key: Key) {
        var resumptions = __Array<Buffer<Storage::Storage<Memory.Allocator<Memory.Heap>>.Contiguous<Async.Waiter.Resumption>>.Linear>(initialCapacity: 0)
        _storage.withLock { state in

            if let existingEntry = state.entries[key],
                case .computing(let waiters) = existingEntry.state
            {
                waiters.queue.drain { waiterEntry in
                    resumptions.append(waiterEntry.resumption(with: .success(value)))
                }
            }

            state.keep(value, for: key)
        }

        resumptions.drain { $0.resume() }
    }

    @discardableResult
    @inlinable
    public func removeValue(
        for key: Key,
        when condition: @Sendable (Value) -> Bool
    ) -> Value? {
        let captured = _storage.withLock { state -> (UInt64, Value)? in
            guard let entry = state.entries[key],
                case .ready(let value) = entry.state
            else {
                return nil
            }

            return (entry.number, value)
        }

        guard let (number, value) = captured, condition(value) else {
            return nil
        }

        return _storage.withLock { state in
            guard let current = state.entries[key],
                current.number == number,
                case .ready = current.state
            else {
                return nil
            }

            state.entries.removeValue(forKey: key)
            return value
        }
    }

    @discardableResult
    @inlinable
    public func removeValue(for key: Key) -> Value? {
        var resumptions = __Array<Buffer<Storage::Storage<Memory.Allocator<Memory.Heap>>.Contiguous<Async.Waiter.Resumption>>.Linear>(initialCapacity: 0)
        let value = _storage.withLock { state -> Value? in
            guard let entry = state.entries.removeValue(forKey: key) else {
                return nil
            }

            switch entry.state {
            case .ready(let value):
                return value

            case .computing(let waiters):

                waiters.queue.drain { waiterEntry in
                    resumptions.append(waiterEntry.resumption(with: .failure(CancellationError())))
                }
                return nil
            }
        }

        resumptions.drain { $0.resume() }

        return value
    }

    @inlinable
    public func removeAll() {
        var resumptions = __Array<Buffer<Storage::Storage<Memory.Allocator<Memory.Heap>>.Contiguous<Async.Waiter.Resumption>>.Linear>(initialCapacity: 0)
        _storage.withLock { state in
            for (_, entry) in state.entries {
                if case .computing(let waiters) = entry.state {
                    waiters.queue.drain { waiterEntry in
                        resumptions.append(
                            waiterEntry.resumption(with: .failure(CancellationError()))
                        )
                    }
                }
            }

            state.entries.removeAll()
        }

        resumptions.drain { $0.resume() }
    }
}

extension Cache {

    public func value(
        for key: Key,
        if shouldCompute: Bool,

        compute: @Sendable () async throws -> Value
    ) async throws(Self.Error) -> Value? {

        if let cached = cachedValue(for: key) {
            return cached
        }

        guard shouldCompute else {
            return nil
        }

        return try await value(for: key, compute: compute)
    }
}
