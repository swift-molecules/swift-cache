import Cache
import Cardinal
import Synchronization
import Testing

@Suite struct `Cache.Traces Tests` {
    @Test func `a value is made once for equal keys`() {
        let table = Cache<Int, String>.Traces<Bool>(capacity: 64)
        let first = table.value(for: 1) { "a" }
        let second = table.value(for: 1) { "b" }
        #expect(first.value == "a")
        #expect(!first.found)
        #expect(second.value == "a")
        #expect(second.found)
        #expect(second.number == first.number)
        #expect(table.counted == .init(found: 1, made: 1))
    }

    @Test func `values are numbered apart`() {
        let table = Cache<Int, Int>.Traces<Bool>(capacity: 1024)
        let numbers = (0..<200).compactMap { key in table.value(for: key) { key }.number }
        #expect(Set(numbers).count == 200)
    }

    @Test func `a key keeps the latest few values and finds the one that holds`() {
        let table = Cache<String, Int>.Traces<Int>(capacity: 64, variants: 2)
        func ask(_ answer: Int) -> Bool {
            table.value(for: "x", under: answer, where: { $0 == answer }) { answer }.found
        }
        #expect(!ask(1))
        #expect(!ask(2))
        #expect(ask(1))
        #expect(!ask(3))
        #expect(ask(2))
        #expect(!ask(1))
    }

    @Test func `a value that is not kept is made again`() {
        let table = Cache<Int, Int>.Traces<Bool>(capacity: 64)
        func ask() -> (found: Bool, number: Int?) {
            let made = table.value(for: 1, under: true, where: { _ in true }, keeps: { _ in false }) { 1 }
            return (made.found, made.number)
        }
        #expect(ask() == (false, nil))
        #expect(ask() == (false, nil))
    }

    @Test func `a failure is thrown and not kept`() {
        struct Failure: Error {}
        let table = Cache<Int, Int>.Traces<Bool>(capacity: 64)
        #expect(throws: Failure.self) { try table.value(for: 1) { () throws(Failure) -> Int in throw Failure() } }
        #expect(table.value(for: 1) { 2 }.value == 2)
    }

    @Test func `a key not asked for during a whole span is forgotten`() {
        let table = Cache<Int, Int>.Traces<Bool>(capacity: 1)
        for key in 0..<400 { _ = table.value(for: key) { key } }
        #expect(table.counted.made == 400)
        #expect(table.counted.forgotten >= 400 - 2 * 16)
        #expect(!table.value(for: 0) { 0 }.found)
    }

    @Test func `those that ask for one key at once make one value`() async {
        let table = Cache<Int, Int>.Traces<Bool>(capacity: 64)
        let made = Atomic<Int>(0)
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<32 {
                group.addTask { table.value(for: 7) { made.add(1, ordering: .relaxed).newValue }.value }
            }
            for await value in group { #expect(value == 1) }
        }
        #expect(made.load(ordering: .relaxed) == 1)
    }
}
