extension Cache.Entry {

    @usableFromInline
    enum State {

        case computing(Waiters)

        case ready(Value)
    }
}
