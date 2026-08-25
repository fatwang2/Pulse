import Foundation

public enum AgentWatchlistError: Error, Equatable, Sendable {
    case groupNotFound(UUID)
    case symbolNotFound(AgentSymbolRef)
    case invalidSymbol(AgentSymbolRef)
    case invalidName
    case duplicateGroupName(String)
    case lastGroupProtected
    case positionNotSupported
    case itemNotOnWatchlist
    case invalidQuantity
    case invalidPrice
    case transactionNotFound(UUID)
    case searchUnavailable
    case searchFailed(String)
    /// `group_ids` is not a permutation of the current watchlist groups.
    case invalidGroupOrder
    /// `symbols` is not a permutation of the target group's members.
    case invalidSymbolOrder
}
