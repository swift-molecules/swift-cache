public import Async
public import Async_Waiter
import Memory
public import Memory_Allocator_Protocol
public import Queue

extension Cache.Entry {

    /// The callers waiting for a value in the making. It stays inside the cache's lock.
    @usableFromInline
    final class Waiters {
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
    typealias Outcome = Result<Value, any Swift::Error>

}
