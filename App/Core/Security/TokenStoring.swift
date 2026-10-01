protocol TokenStoring: Sendable {
    func save(_ tokens: AuthTokens) throws
    func load() -> AuthTokens?
    func clear() throws
}
