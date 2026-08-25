public protocol AgentSymbolSearching: Sendable {
    func search(_ query: String) async throws -> [SymbolInfo]
}
