import Foundation

@MainActor
public struct AgentWatchlistCommands {
    private let store: WatchlistStore
    private let market: MarketStore?
    private let searcher: (any AgentSymbolSearching)?

    public init(
        store: WatchlistStore,
        market: MarketStore? = nil,
        searcher: (any AgentSymbolSearching)? = nil
    ) {
        self.store = store
        self.market = market
        self.searcher = searcher
    }

    public func listWatchlists() -> AgentWatchlistSnapshot {
        AgentWatchlistSnapshot(groups: store.groups.map(groupSnapshot))
    }

    public func listPositions() -> [AgentPositionSnapshot] {
        store.allItems
            .filter(\.hasPositionHistory)
            .map(positionSnapshot)
    }

    public func quotes(for symbols: [AgentSymbolRef]) -> [AgentQuoteSnapshot] {
        guard let market else { return [] }
        return symbols.compactMap { ref in
            guard let symbol = symbol(from: ref), let quote = market.quote(for: symbol) else {
                return nil
            }
            return quoteSnapshot(quote)
        }
    }

    public func searchSymbols(
        _ query: String
    ) async -> Result<[AgentInstrument], AgentWatchlistError> {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .success([]) }
        guard let searcher else { return .failure(.searchUnavailable) }
        do {
            return .success(try await searcher.search(query).map(instrument))
        } catch {
            return .failure(.searchFailed(error.localizedDescription))
        }
    }

    public func createGroup(
        named name: String
    ) -> Result<AgentMutation<AgentGroupSnapshot>, AgentWatchlistError> {
        let name = normalizedGroupName(name)
        guard !name.isEmpty else { return .failure(.invalidName) }
        guard !store.groups.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            return .failure(.duplicateGroupName(name))
        }

        let before = Set(store.symbols)
        let previousSelection = store.selectedGroupID
        guard let id = store.createGroup(named: name) else {
            return .failure(.invalidName)
        }
        if let previousSelection {
            store.selectGroup(previousSelection)
        }
        guard let group = store.group(for: id) else {
            return .failure(.groupNotFound(id))
        }
        return .success(mutation(
            groupSnapshot(group),
            before: before,
            alreadyApplied: false
        ))
    }

    public func renameGroup(
        _ id: UUID,
        to name: String
    ) -> Result<AgentGroupSnapshot, AgentWatchlistError> {
        guard let group = store.group(for: id) else {
            return .failure(.groupNotFound(id))
        }
        let name = normalizedGroupName(name)
        guard !name.isEmpty else { return .failure(.invalidName) }
        guard !store.groups.contains(where: {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            return .failure(.duplicateGroupName(name))
        }
        if group.name != name {
            guard store.renameGroup(id, to: name) else {
                return .failure(.invalidName)
            }
        }
        guard let renamed = store.group(for: id) else {
            return .failure(.groupNotFound(id))
        }
        return .success(groupSnapshot(renamed))
    }

    public func deleteGroup(
        _ id: UUID
    ) -> Result<AgentMutation<Void>, AgentWatchlistError> {
        let before = Set(store.symbols)
        guard store.group(for: id) != nil else {
            return .success(mutation((), before: before, alreadyApplied: true))
        }
        guard store.groups.count > 1 else {
            return .failure(.lastGroupProtected)
        }
        guard store.deleteGroup(id) else {
            return .failure(.groupNotFound(id))
        }
        return .success(mutation((), before: before, alreadyApplied: false))
    }

    /// Sets tag-bar order. `orderedIDs` must list every current group exactly once.
    public func reorderGroups(
        _ orderedIDs: [UUID]
    ) -> Result<AgentMutation<AgentWatchlistSnapshot>, AgentWatchlistError> {
        let currentIDs = store.groups.map(\.id)
        guard Set(orderedIDs).count == orderedIDs.count,
              orderedIDs.count == currentIDs.count,
              Set(orderedIDs) == Set(currentIDs) else {
            return .failure(.invalidGroupOrder)
        }

        let before = Set(store.symbols)
        let alreadyApplied = orderedIDs == currentIDs
        if !alreadyApplied {
            guard store.reorderGroups(orderedIDs) else {
                return .failure(.invalidGroupOrder)
            }
        }
        return .success(mutation(
            listWatchlists(),
            before: before,
            alreadyApplied: alreadyApplied
        ))
    }

    /// Sets Custom Order for a group. Pin membership is unchanged; the stored order is
    /// coerced to pinned-first using relative order within each section from `refs`.
    public func reorderSymbols(
        _ refs: [AgentSymbolRef],
        in groupID: UUID
    ) -> Result<AgentMutation<AgentGroupSnapshot>, AgentWatchlistError> {
        guard let group = store.group(for: groupID) else {
            return .failure(.groupNotFound(groupID))
        }

        var symbols: [SymbolID] = []
        symbols.reserveCapacity(refs.count)
        var seen = Set<SymbolID>()
        for ref in refs {
            guard let symbol = symbol(from: ref) else {
                return .failure(.invalidSymbol(ref))
            }
            guard !seen.contains(symbol) else {
                return .failure(.invalidSymbolOrder)
            }
            seen.insert(symbol)
            symbols.append(symbol)
        }

        guard symbols.count == group.symbols.count,
              Set(symbols) == Set(group.symbols) else {
            return .failure(.invalidSymbolOrder)
        }

        let pinned = Set(group.pinnedSymbols)
        let pinnedOrdered = symbols.filter { pinned.contains($0) }
        let expectedVisible = pinnedOrdered + symbols.filter { !pinned.contains($0) }
        let alreadyApplied = group.symbols == expectedVisible
            && group.pinnedSymbols == pinnedOrdered

        let before = Set(store.symbols)
        if !alreadyApplied {
            guard store.applyCustomOrder(symbols, in: groupID) else {
                return .failure(.invalidSymbolOrder)
            }
        }
        guard let updated = store.group(for: groupID) else {
            return .failure(.groupNotFound(groupID))
        }
        return .success(mutation(
            groupSnapshot(updated),
            before: before,
            alreadyApplied: alreadyApplied
        ))
    }

    public func addSymbol(
        _ ref: AgentSymbolRef,
        name: String? = nil,
        type: InstrumentType? = nil,
        to groupID: UUID
    ) -> Result<AgentMutation<AgentInstrument>, AgentWatchlistError> {
        guard store.group(for: groupID) != nil else {
            return .failure(.groupNotFound(groupID))
        }
        guard let symbol = symbol(from: ref) else {
            return .failure(.invalidSymbol(ref))
        }

        let before = Set(store.symbols)
        let alreadyApplied = store.contains(symbol, in: groupID)
        let resolvedName = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? symbol.displayCode
        store.add(
            SymbolInfo(
                symbol: symbol,
                name: resolvedName,
                type: type ?? inferredType(for: symbol)
            ),
            to: groupID
        )
        guard let item = store.item(for: symbol) else {
            return .failure(.symbolNotFound(ref))
        }
        return .success(mutation(
            instrument(item),
            before: before,
            alreadyApplied: alreadyApplied
        ))
    }

    public func removeSymbol(
        _ ref: AgentSymbolRef,
        from groupID: UUID
    ) -> Result<AgentMutation<Void>, AgentWatchlistError> {
        guard store.group(for: groupID) != nil else {
            return .failure(.groupNotFound(groupID))
        }
        guard let symbol = symbol(from: ref) else {
            return .failure(.invalidSymbol(ref))
        }
        let before = Set(store.symbols)
        let alreadyApplied = !store.contains(symbol, in: groupID)
        store.setMembership(symbol, in: groupID, included: false)
        return .success(mutation((), before: before, alreadyApplied: alreadyApplied))
    }

    public func recordTrade(
        _ draft: AgentTradeDraft
    ) -> Result<AgentMutation<AgentPositionSnapshot>, AgentWatchlistError> {
        guard draft.quantity.isFinite, draft.quantity > 0 else {
            return .failure(.invalidQuantity)
        }
        guard draft.price.isFinite, draft.price > 0 else {
            return .failure(.invalidPrice)
        }
        guard let symbol = symbol(from: draft.symbol) else {
            return .failure(.invalidSymbol(draft.symbol))
        }
        guard let item = store.item(for: symbol) else {
            return .failure(.itemNotOnWatchlist)
        }
        guard item.supportsPosition else {
            return .failure(.positionNotSupported)
        }

        let before = Set(store.symbols)
        if let id = draft.id, item.transactions.contains(where: { $0.id == id }) {
            return .success(mutation(
                positionSnapshot(item),
                before: before,
                alreadyApplied: true
            ))
        }
        store.addTransaction(symbol, PositionTransaction(
            id: draft.id ?? UUID(),
            kind: draft.kind.positionKind,
            price: draft.price,
            quantity: draft.quantity,
            date: draft.date
        ))
        guard let updated = store.item(for: symbol) else {
            return .failure(.itemNotOnWatchlist)
        }
        return .success(mutation(
            positionSnapshot(updated),
            before: before,
            alreadyApplied: false
        ))
    }

    public func deleteTrade(
        symbol ref: AgentSymbolRef,
        id: UUID
    ) -> Result<AgentMutation<AgentPositionSnapshot>, AgentWatchlistError> {
        guard let symbol = symbol(from: ref) else {
            return .failure(.invalidSymbol(ref))
        }
        guard let item = store.item(for: symbol) else {
            return .failure(.itemNotOnWatchlist)
        }

        let before = Set(store.symbols)
        let alreadyApplied = !item.transactions.contains(where: { $0.id == id })
        if !alreadyApplied {
            store.deleteTransaction(symbol, id: id)
        }
        guard let updated = store.item(for: symbol) else {
            return .failure(.itemNotOnWatchlist)
        }
        return .success(mutation(
            positionSnapshot(updated),
            before: before,
            alreadyApplied: alreadyApplied
        ))
    }

    public func calibratePosition(
        symbol ref: AgentSymbolRef,
        quantity: Double,
        averageCost: Double,
        date: Date,
        id: UUID?
    ) -> Result<AgentMutation<AgentPositionSnapshot>, AgentWatchlistError> {
        guard quantity.isFinite else {
            return .failure(.invalidQuantity)
        }
        guard averageCost.isFinite, averageCost >= 0 else {
            return .failure(.invalidPrice)
        }
        guard let symbol = symbol(from: ref) else {
            return .failure(.invalidSymbol(ref))
        }
        guard let item = store.item(for: symbol) else {
            return .failure(.itemNotOnWatchlist)
        }
        guard item.supportsPosition else {
            return .failure(.positionNotSupported)
        }

        let before = Set(store.symbols)
        if let id, item.transactions.contains(where: { $0.id == id }) {
            return .success(mutation(
                positionSnapshot(item),
                before: before,
                alreadyApplied: true
            ))
        }
        store.calibratePosition(
            symbol,
            quantity: quantity,
            averageCost: averageCost,
            date: date,
            id: id ?? UUID()
        )
        guard let updated = store.item(for: symbol) else {
            return .failure(.itemNotOnWatchlist)
        }
        return .success(mutation(
            positionSnapshot(updated),
            before: before,
            alreadyApplied: false
        ))
    }

    private func mutation<Value: Sendable>(
        _ value: Value,
        before: Set<SymbolID>,
        alreadyApplied: Bool
    ) -> AgentMutation<Value> {
        AgentMutation(
            value: value,
            didChangeSymbolUnion: before != Set(store.symbols),
            alreadyApplied: alreadyApplied
        )
    }

    private func groupSnapshot(_ group: WatchlistGroup) -> AgentGroupSnapshot {
        AgentGroupSnapshot(
            id: group.id,
            name: group.name,
            symbols: store.items(in: group.id).map(instrument)
        )
    }

    private func positionSnapshot(_ item: WatchItem) -> AgentPositionSnapshot {
        AgentPositionSnapshot(
            symbol: instrument(item),
            quantity: item.positionQuantity,
            averageCost: item.averageCost,
            costBasis: item.costBasis,
            realizedPnL: item.realizedPnL,
            transactions: item.transactions.map(transactionSnapshot),
            quote: market?.quote(for: item.symbol).map(quoteSnapshot)
        )
    }

    private func instrument(_ item: WatchItem) -> AgentInstrument {
        AgentInstrument(
            market: item.symbol.market.rawValue,
            code: item.symbol.code,
            displayCode: item.symbol.displayCode,
            name: item.resolvedDisplayName,
            type: item.resolvedInstrumentType?.rawValue,
            supportsPosition: item.supportsPosition
        )
    }

    private func instrument(_ info: SymbolInfo) -> AgentInstrument {
        instrument(WatchItem(
            symbol: info.symbol,
            displayName: info.resolvedDisplayName,
            displayNameSource: info.displayNameSource,
            instrumentType: info.type
        ))
    }

    private func transactionSnapshot(_ transaction: PositionTransaction) -> AgentTransaction {
        AgentTransaction(
            id: transaction.id,
            kind: transaction.kind.rawValue,
            price: transaction.price,
            quantity: transaction.quantity,
            date: formattedDay(transaction.date)
        )
    }

    private func quoteSnapshot(_ quote: Quote) -> AgentQuoteSnapshot {
        AgentQuoteSnapshot(
            price: quote.price,
            previousClose: quote.previousClose,
            changePercent: quote.changePercent,
            currencyCode: quote.currencyCode,
            timestamp: quote.timestamp,
            marketState: quote.marketState?.rawValue
        )
    }

    private func symbol(from ref: AgentSymbolRef) -> SymbolID? {
        let rawMarket = ref.market.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = ref.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let market = Market(rawValue: rawMarket), !code.isEmpty else {
            return nil
        }
        return SymbolID(market: market, code: code)
    }

    private func inferredType(for symbol: SymbolID) -> InstrumentType {
        if symbol.indexID != nil { return .index }
        if symbol.metalID != nil { return .commodity }
        if symbol.cryptoPair != nil { return .crypto }
        return .equity
    }

    private func normalizedGroupName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
    }

    /// Trade dates are calendar days in the user's own zone — that is how the
    /// app enters and displays them — so they read back in that zone too.
    /// Formatting in UTC shifted every entry east of Greenwich to the previous
    /// day: a trade the user dated September 2 came back as September 1.
    private func formattedDay(_ date: Date) -> String {
        let day = CalendarDay(date, in: .current)
        return String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }
}

private extension AgentTradeKind {
    var positionKind: PositionTransaction.Kind {
        switch self {
        case .buy: .buy
        case .sell: .sell
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
