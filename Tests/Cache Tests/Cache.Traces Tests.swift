import Cache
import Cardinal
import Hash_Table_Primitive
import Testing

@Suite struct `Cache.Traces Tests` {
    @Test func `a value is made once for equal keys`() {
        var table = Cache<Int, String>.Traces(capacity: 64)
        let first = table.value(for: 1) { "a" }
        let second = table.value(for: 1) { "b" }
        #expect(first.value == "a")
        #expect(second.value == "a")
        #expect(second.number == first.number)
        #expect(table.counted == .init(found: 1, made: 1))
    }

    @Test func `values are numbered apart`() {
        var table = Cache<Int, Int>.Traces(capacity: 1024)
        let numbers = (0..<200).map { key in table.value(for: key) { key }.number }
        #expect(Set(numbers).count == 200)
    }

    @Test func `a key keeps the latest few values and finds the one that holds`() {
        var table = Cache<String, Int>.Traces(capacity: 64, variants: 2)
        func ask(_ answer: Int) -> Bool {
            let key = Hash.Once("x")
            if table.found(key, where: { $0 == answer }) != nil { return true }
            table.keep(answer, for: key)
            return false
        }
        #expect(!ask(1))
        #expect(!ask(2))
        #expect(ask(1))
        #expect(!ask(3))
        #expect(ask(2))
        #expect(!ask(1))
    }

    @Test func `a value made outside the table may ask the table while it is made`() {
        var table = Cache<Int, Int>.Traces(capacity: 64)
        func sum(to number: Int) -> Int {
            let key = Hash.Once(number)
            if let found = table.found(key) { return found.value }
            return table.keep(number == 0 ? 0 : number + sum(to: number - 1), for: key).value
        }
        #expect(sum(to: 10) == 55)
        #expect(table.counted == .init(made: 11))
        #expect(sum(to: 9) == 45)
        #expect(table.counted == .init(found: 1, made: 11))
    }

    @Test func `a failure is thrown and not kept`() {
        struct Failure: Error {}
        var table = Cache<Int, Int>.Traces(capacity: 64)
        #expect(throws: Failure.self) { try table.value(for: 1) { () throws(Failure) -> Int in throw Failure() } }
        #expect(table.value(for: 1) { 2 }.value == 2)
    }

    @Test func `a key not asked for during a whole span is forgotten`() {
        var table = Cache<Int, Int>.Traces(capacity: 10)
        for key in 0..<400 { _ = table.value(for: key) { key } }
        #expect(table.counted == .init(made: 400, forgotten: 380))
        #expect(table.found(Hash.Once(0)) == nil)
        #expect(table.found(Hash.Once(399)) != nil)
    }
}
