extension Cache {

    @usableFromInline
    enum Action {
        case returnValue(Value)

        case join(UInt64)
        case compute(UInt64)
    }
}
