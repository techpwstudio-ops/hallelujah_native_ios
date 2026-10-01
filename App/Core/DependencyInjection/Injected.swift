@propertyWrapper
struct Injected<Value> {
    var wrappedValue: Value

    init() {
        wrappedValue = DependencyContainer.current.resolve()
    }
}
