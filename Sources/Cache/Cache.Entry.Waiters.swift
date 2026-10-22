public import Async
public import Async_Waiter
import Memory
public import Memory_Allocator_Protocol
public import Queue

extension Cache.Entry {

    @usableFromInline

    final class Waiters: @unchecked Sendable {
        @usableFromInline
        var queue: Async.Waiter.Queue.Unbounded<Outcome, Void>

        @inlinable
        package init() {
            self.queue = Async.Waiter.Queue.Unbounded<Outcome, Void>()
        }
    }
}

extension Cache.Entry.Waiters {

    @usableFromInline
    // swiftlint:disable:next no_any_protocol_existential  // reason: Waiters deliver caller-defined compute errors.
    typealias Outcome = Result<Value, any Swift::Error>

}
