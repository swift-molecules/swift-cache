import Cache
import Cardinal
import Testing

@Suite struct `Cache.Spans Tests` {
    @Test func `a kept value is found again`() {
        var spans = Cache<Int, String>.Spans(capacity: 2)
        spans.keep("a", for: 1)
        #expect(spans.value(for: 1) == "a")
        #expect(spans.value(for: 2) == nil)
    }

    @Test func `an entry not used for a whole span is forgotten`() {
        var spans = Cache<Int, String>.Spans(capacity: 2)
        spans.keep("a", for: 1)
        spans.keep("b", for: 2)
        spans.keep("c", for: 3)  // starts a span: 1 and 2 are the span before
        spans.keep("d", for: 4)
        spans.keep("e", for: 5)  // starts a span: 1 and 2 are let go
        #expect(!spans.contains(1))
        #expect(!spans.contains(2))
        #expect(spans.value(for: 3) == "c")
        #expect(spans.count == 3)
    }

    @Test func `reading an entry of the span before carries it into this one`() {
        var spans = Cache<Int, String>.Spans(capacity: 2)
        spans.keep("a", for: 1)
        spans.keep("b", for: 2)
        spans.keep("c", for: 3)  // 1 and 2 are the span before
        #expect(spans.value(for: 1) == "a")  // carried into this span, which is now full
        spans.keep("d", for: 4)  // starts a span: 3 and 1 are the span before
        #expect(spans.contains(1))
        #expect(!spans.contains(2))
    }

    @Test func `replacing a key this span holds does not start a span`() {
        var spans = Cache<Int, String>.Spans(capacity: 1)
        spans.keep("a", for: 1)
        spans.keep("b", for: 1)
        #expect(spans.value(for: 1) == "b")
        #expect(spans.count == 1)
    }

    @Test func `make runs only when no span holds the key`() {
        var spans = Cache<Int, Int>.Spans(capacity: 4)
        var made = 0
        for _ in 0..<3 {
            _ = spans.value(for: 7) {
                made += 1
                return 49
            }
        }
        #expect(made == 1)
        #expect(spans.value(for: 7) == 49)
    }

    @Test func `a value that is not Sendable is kept under the plain name`() {
        final class Held {
            let name: String

            init(_ name: String) {
                self.name = name
            }
        }
        var spans = __CacheSpans<Int, Held>(capacity: 2)
        spans.keep(Held("a"), for: 1)
        #expect(spans.value(for: 1)?.name == "a")
    }

    @Test func `a span holds its capacity in cost, and the span let go is given back`() {
        var spans = Cache<Int, String>.Spans(capacity: 10)
        #expect(spans.keep("a", for: 1, cost: 6).isEmpty)
        #expect(spans.keep("b", for: 2, cost: 6).isEmpty)  // 12 held: the next new key starts a span
        #expect(spans.keep("c", for: 3, cost: 1).isEmpty)  // 1 and 2 are the span before; nothing was before them
        #expect(spans.value(for: 1) == "a")  // carried over with its cost: 7 held
        #expect(spans.keep("d", for: 4, cost: 5).isEmpty)  // 12 held
        #expect(spans.keep("e", for: 5) == [2: "b"])  // starts a span: 2, never read, is let go and given
        #expect(!spans.contains(2))
        #expect(spans.contains(1))
    }
}
