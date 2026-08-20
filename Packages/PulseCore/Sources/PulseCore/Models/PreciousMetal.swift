import Foundation

/// Provider-independent identity of a precious metal contract. Like indices,
/// metals have no single exchange ticker: COMEX gold is `hf_GC` at Tencent and
/// `GC=F` at Yahoo, so Pulse owns the identity and each provider maps it to its
/// own wire format.
///
/// Both the exchange-traded contracts and London spot are modeled. Spot is the
/// price most people in China mean by "黄金", and it trades several percent away
/// from the COMEX contract, so the two are separate instruments rather than one
/// with two sources.
/// Declaration order is presentation order: it ranks equally-good search hits
/// and lays out the category listing. Spot leads because that is what both
/// "黄金" and "gold" mean in practice — search-completion data and the Chinese
/// gold portals agree, and the latter rank COMEX last — then the global
/// benchmark contract, then the regional one.
public enum PreciousMetalID: String, Codable, Sendable, CaseIterable, Hashable {
    case goldSpot
    case gold
    case shanghaiGoldSpot
    case shanghaiGold
    case silverSpot
    case silver
    case shanghaiSilver
    case platinum
    case palladium

    /// Physical metal rather than a dated contract — London OTC for the dollar
    /// prices, the Shanghai Gold Exchange's fully-paid Au99.99 for the yuan one.
    /// Only the Chinese sources carry any of them: Yahoo has never had a working
    /// spot symbol.
    public var isSpot: Bool {
        switch self {
        case .goldSpot, .silverSpot, .shanghaiGoldSpot: true
        case .gold, .silver, .platinum, .palladium, .shanghaiGold, .shanghaiSilver: false
        }
    }

    /// Which market's currency and session this contract follows. Shanghai
    /// prices in CNY on the SHFE session; everything else in USD.
    public var market: Market {
        switch self {
        case .shanghaiGoldSpot, .shanghaiGold, .shanghaiSilver: .metalCN
        case .gold, .goldSpot, .silver, .silverSpot, .platinum, .palladium: .metal
        }
    }

    /// Stable user-facing shorthand; providers must not send this value directly.
    public var displayCode: String {
        switch self {
        case .gold: "GC"
        case .goldSpot: "XAU"
        case .silver: "SI"
        case .silverSpot: "XAG"
        case .platinum: "PL"
        case .palladium: "PA"
        case .shanghaiGoldSpot: "AU9999"
        case .shanghaiGold: "AU0"
        case .shanghaiSilver: "AG0"
        }
    }

    /// Provider-independent, localized name used everywhere Pulse presents the
    /// metal. Raw provider names remain quote metadata and never replace this.
    public var displayName: String {
        let key = "metal.\(rawValue)"
        let localized = PulseLocalization.localizedString(key)
        guard localized == key else { return localized }
        return fallbackDisplayName(
            chinese: PulseLocalization.currentLanguageIdentifier.hasPrefix("zh")
        )
    }

    /// Used only when the localized table has no entry — a build that ships
    /// without it, or a key someone forgot. It carries just the two languages
    /// this type can spell without help, and a test keeps it honest against the
    /// shipped tables.
    func fallbackDisplayName(chinese: Bool) -> String {
        switch self {
        case .gold: chinese ? "纽约金" : "COMEX Gold"
        case .goldSpot: chinese ? "伦敦金" : "London Gold Spot"
        case .silver: chinese ? "纽约银" : "COMEX Silver"
        case .silverSpot: chinese ? "伦敦银" : "London Silver Spot"
        case .platinum: chinese ? "纽约铂金" : "NYMEX Platinum"
        case .palladium: chinese ? "纽约钯金" : "NYMEX Palladium"
        case .shanghaiGoldSpot: chinese ? "上海金" : "Shanghai Gold Spot"
        case .shanghaiGold: chinese ? "沪金主连" : "SHFE Gold"
        case .shanghaiSilver: chinese ? "沪银主连" : "SHFE Silver"
        }
    }

    /// Listing venue, shown in search results the way an exchange name is.
    public var exchangeName: String {
        switch self {
        case .gold, .silver: "COMEX"
        case .platinum, .palladium: "NYMEX"
        case .goldSpot, .silverSpot: "London"
        case .shanghaiGoldSpot: "SGE"
        case .shanghaiGold, .shanghaiSilver: "SHFE"
        }
    }

    /// Code written alongside `metalID` so the immediately preceding app version
    /// can still decode a new watchlist snapshot: it reads the entry as a US
    /// symbol, which Yahoo happens to quote correctly.
    var backwardCompatibleCode: String { "\(displayCode)=F" }

    /// Every code that names this contract on the wire: Pulse's shorthand plus
    /// each provider's own symbol for it. Tencent labels the platinum-group
    /// contracts `XPT` / `XPD` while quoting the same NYMEX futures Yahoo serves
    /// as `PL=F` / `PA=F`.
    private var acceptedCodes: [String] {
        switch self {
        case .gold: ["GC"]
        case .goldSpot: ["XAU", "XAUUSD"]
        case .silver: ["SI"]
        case .silverSpot: ["XAG", "XAGUSD"]
        case .platinum: ["PL", "XPT"]
        case .palladium: ["PA", "XPD"]
        case .shanghaiGoldSpot: ["AU9999", "AU99.99"]
        case .shanghaiGold: ["AU0", "AU"]
        case .shanghaiSilver: ["AG0", "AG"]
        }
    }

    /// Recognizes the codes Pulse itself may hand back — canonical shorthand,
    /// both providers' wire symbols, and the backward-compatible US code — and
    /// collapses them to one semantic identity. Search aliases are deliberately
    /// not accepted here: identity must stay exact, so a spot code such as `XAU`,
    /// which is a different instrument, never becomes a futures contract.
    static func resolve(market: Market, code rawCode: String) -> PreciousMetalID? {
        var code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if code.hasPrefix("HF_") { code.removeFirst(3) }
        if code.hasSuffix("=F") { code.removeLast(2) }
        switch market {
        case .jp, .kr, .kq:
            return nil
        case .metal, .metalCN:
            // Either metal market accepts any metal code; the identity itself
            // decides which market it really belongs to.
            return allCases.first { $0.acceptedCodes.contains(code) }
        case .us:
            // A US ticker only becomes a metal in the unambiguous futures
            // notation Yahoo uses, so no listed equity can be hijacked.
            guard rawCode.uppercased().hasSuffix("=F") else { return nil }
            return allCases.first { $0.acceptedCodes.contains(code) }
        case .hk, .sh, .sz, .crypto:
            return nil
        }
    }
}

/// Pulse's own search index for metals. Tencent's smartbox does not know the
/// `hf_` channel at all ("黄金", "伦敦金", "hf" all return nothing), so the only
/// way to reach these instruments is a catalog the app carries itself.
public enum PreciousMetalCatalog {
    /// Names, tickers, spot codes, and pinyin a user may plausibly type. Spot
    /// codes are included on purpose: someone searching "XAU" wants the gold
    /// row, and the result names the contract it actually is.
    private static let aliases: [PreciousMetalID: [String]] = [
        .gold: ["GC", "GCF", "GOLD", "COMEX GOLD", "COMEX",
                "黄金", "黃金", "纽约黄金", "纽约金", "美黄金", "金", "HUANGJIN", "HJ",
                "ゴールド", "きん"],
        .goldSpot: ["XAU", "XAUUSD", "SPOT GOLD", "LONDON GOLD", "GOLD",
                    "伦敦金", "倫敦金", "现货黄金", "现货金", "黄金", "金",
                    "HUANGJIN", "HJ", "LUNDUNJIN",
                    "ロンドン金", "スポット金"],
        .silver: ["SI", "SIF", "SILVER", "COMEX SILVER",
                  "白银", "白銀", "纽约白银", "纽约银", "美白银", "银", "BAIYIN", "BY",
                  "シルバー", "ぎん"],
        .silverSpot: ["XAG", "XAGUSD", "SPOT SILVER", "LONDON SILVER", "SILVER",
                      "伦敦银", "倫敦銀", "现货白银", "现货银", "白银", "银",
                      "BAIYIN", "BY", "LUNDUNYIN",
                      "ロンドン銀"],
        .platinum: ["PL", "PLF", "XPT", "XPTUSD", "PLATINUM", "NYMEX PLATINUM",
                    "铂金", "白金", "纽约铂金", "BOJIN", "BJ",
                    "プラチナ", "はっきん"],
        .palladium: ["PA", "PAF", "XPD", "XPDUSD", "PALLADIUM", "NYMEX PALLADIUM",
                     "钯金", "鈀金", "纽约钯金", "BAJIN",
                     "パラジウム"],
        .shanghaiGoldSpot: ["AU9999", "AU99.99", "AU999", "SGE GOLD", "SHANGHAI GOLD",
                            "上海金", "上海黄金", "沪金99", "黄金9999", "沪金", "黄金", "金",
                            "SHANGHAIJIN",
                            "上海金", "上海ゴールド"],
        .shanghaiGold: ["AU0", "AU", "SHFE GOLD", "SHFE",
                        "沪金", "滬金", "沪金主连", "沪金期货", "黄金", "金",
                        "HUJIN",
                        "上海金先物"],
        .shanghaiSilver: ["AG0", "AG", "SHFE SILVER", "SHANGHAI SILVER",
                          "沪银", "滬銀", "上海银", "上海白银", "沪银主连", "白银", "银",
                          "HUYIN", "SHANGHAIBAIYIN",
                          "上海銀"],
    ]

    /// Words that name the raw contract rather than a company: someone typing
    /// "黄金期货" or "spot gold" means this instrument, while "山东黄金" means a
    /// listed miner. Stripping them (instead of matching any query that merely
    /// contains "黄金") keeps the catalog out of equity searches.
    private static let contractQualifiers = [
        "期货", "期貨", "现货", "現貨", "主连", "连续", "价格", "行情",
        "伦敦", "倫敦", "纽约", "紐約", "上海",
    ]
    private static let englishQualifiers: Set<String> = [
        "FUTURES", "FUTURE", "SPOT", "PRICE", "LONDON", "COMEX", "NYMEX",
        "SHANGHAI", "SHFE",
    ]

    /// Which of the two instruments behind the same metal the user named. "黄金"
    /// alone means either, and offering both is the honest answer; "现货黄金" and
    /// "黄金期货" each name exactly one.
    private enum ContractIntent {
        /// "现货黄金" / "spot gold" means the London contract in everyday use,
        /// even though Shanghai's Au99.99 is physically spot as well — that one
        /// is reached by naming the venue.
        case spot
        case shanghai
        case exchange

        static func detected(in query: String) -> ContractIntent? {
            let spotMarkers = ["现货", "現貨", "伦敦", "倫敦", "SPOT", "LONDON"]
            let shanghaiMarkers = ["沪", "滬", "上海", "SHANGHAI", "SHFE"]
            let exchangeMarkers = ["期货", "期貨", "主连", "连续", "纽约", "紐約",
                                   "FUTURES", "FUTURE", "COMEX", "NYMEX"]
            // Shanghai is checked first: "沪金期货" names a venue and a kind, and
            // the venue is the more specific of the two.
            if shanghaiMarkers.contains(where: query.contains) { return .shanghai }
            if spotMarkers.contains(where: query.contains) { return .spot }
            if exchangeMarkers.contains(where: query.contains) { return .exchange }
            return nil
        }

        func matches(_ metal: PreciousMetalID) -> Bool {
            switch self {
            case .spot: metal.isSpot && metal.market == .metal
            case .shanghai: metal.market == .metalCN
            case .exchange: !metal.isSpot && metal.market == .metal
            }
        }
    }

    /// The category itself is a search term — it is what this market is called.
    private static let categoryAliases = [
        "贵金属", "貴金属", "METAL", "METALS", "PRECIOUS METAL", "PRECIOUS METALS",
    ]

    public static func search(_ rawQuery: String) -> [SymbolInfo] {
        matches(rawQuery).map { metal in
            SymbolInfo(
                symbol: SymbolID(metal: metal),
                name: metal.displayName,
                exchangeName: metal.exchangeName,
                type: .commodity
            )
        }
    }

    static func matches(_ rawQuery: String) -> [PreciousMetalID] {
        let intent = ContractIntent.detected(
            in: rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        )
        let query = normalized(rawQuery)
        guard !query.isEmpty else { return [] }
        // A single latin letter matches half the catalog by substring and reads
        // as noise; CJK characters are words, so one is enough to search on.
        guard query.count > 1 || !query.allSatisfy(\.isASCII) else { return [] }

        // Asking for the category lists it, in the order the metals matter.
        if categoryAliases.contains(where: { $0 == query || $0.hasPrefix(query) }) {
            return PreciousMetalID.allCases
        }

        let ranked = PreciousMetalID.allCases.compactMap { metal -> (Int, PreciousMetalID)? in
            guard let score = (aliases[metal] ?? []).compactMap({ alias -> Int? in
                if alias == query { return 0 }
                if alias.hasPrefix(query) { return 1 }
                if alias.contains(query) { return 2 }
                return nil
            }).min() else { return nil }
            return (score, metal)
        }
        .sorted { lhs, rhs in
            lhs.0 != rhs.0 ? lhs.0 < rhs.0 : order(of: lhs.1) < order(of: rhs.1)
        }
        .map(\.1)

        guard let intent else { return ranked }
        // Honour the named contract, but never answer nothing because of it:
        // "伦敦铂金" has no spot instrument here and still means platinum.
        let narrowed = ranked.filter(intent.matches)
        return narrowed.isEmpty ? ranked : narrowed
    }

    /// Gold and silver lead: they are what "metals" means to most people, and
    /// platinum group metals follow in the order exchanges list them.
    private static func order(of metal: PreciousMetalID) -> Int {
        PreciousMetalID.allCases.firstIndex(of: metal) ?? .max
    }

    /// Reduces what the user typed to the instrument they named: provider wire
    /// decoration (`hf_GC`, `GC=F`, pasted from a chart URL) and contract
    /// qualifiers come off, so the alias table only has to carry real names.
    private static func normalized(_ rawQuery: String) -> String {
        var query = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if query.hasPrefix("HF_") { query.removeFirst(3) }
        if query.hasSuffix("=F") { query.removeLast(2) }
        let original = query
        // Longest first, so removing "FUTURE" never leaves the "S" of "FUTURES".
        for qualifier in (contractQualifiers + englishQualifiers).sorted(by: { $0.count > $1.count }) {
            query = query.replacingOccurrences(of: qualifier, with: " ")
        }
        query = query
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // "COMEX" or "期货" on its own is the whole query, not a qualifier on one.
        return query.isEmpty ? original : query
    }
}
