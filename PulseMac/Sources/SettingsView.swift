import SwiftUI
import PulseCore

struct ProviderRow: View {
    @Environment(AppState.self) private var appState
    let descriptor: ProviderDescriptor

    var body: some View {
        Toggle(isOn: Binding(
            get: { appState.isProviderEnabled(descriptor.id) },
            set: { appState.setProvider(descriptor.id, enabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.name)
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        let markets = Market.allCases
            .filter { descriptor.markets.contains($0) }
            .map(\.displayName)
            .joined(separator: "/")
        var capabilities: [String] = []
        if descriptor.capabilities.contains(.quotes) { capabilities.append("报价") }
        if descriptor.capabilities.contains(.candles) { capabilities.append("K线") }
        if descriptor.capabilities.contains(.search) { capabilities.append("搜索") }
        if descriptor.capabilities.contains(.streaming) { capabilities.append("推送") }
        let realtime = descriptor.delay.contains { $0.value == 0 } ? "部分实时" : "延时"
        return "\(markets) · \(capabilities.joined(separator: "/")) · \(realtime)"
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Binding var route: PopoverRoute

    var body: some View {
        @Bindable var settings = appState.settings

        VStack(spacing: 0) {
            HStack {
                Button {
                    route = .list
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text("设置").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            Form {
                Section {
                    Toggle("在菜单栏显示行情", isOn: $settings.showPriceInMenuBar)
                    if settings.showPriceInMenuBar {
                        Picker("显示模式", selection: $settings.menuBarMode) {
                            Text(MenuBarMode.single.displayName).tag(MenuBarMode.single)
                            Text(MenuBarMode.rotate.displayName).tag(MenuBarMode.rotate)
                        }
                        if settings.menuBarMode == .single {
                            Picker("固定标的", selection: $settings.primarySymbol) {
                                Text("自选第一个").tag(SymbolID?.none)
                                ForEach(appState.watchlist.items) { item in
                                    Text(item.displayName).tag(SymbolID?.some(item.symbol))
                                }
                            }
                        }
                        if settings.menuBarMode == .rotate {
                            Picker("轮播间隔", selection: $settings.rotateInterval) {
                                Text("3 秒").tag(TimeInterval(3))
                                Text("6 秒").tag(TimeInterval(6))
                                Text("10 秒").tag(TimeInterval(10))
                            }
                        }
                    }
                } header: {
                    Text("菜单栏")
                } footer: {
                    if !settings.showPriceInMenuBar {
                        Text("关闭时菜单栏只显示图标，更低调")
                    }
                }

                Section("行情") {
                    Picker("盘中刷新频率", selection: Binding(
                        get: { settings.refreshInterval },
                        set: { appState.applyRefreshInterval($0) }
                    )) {
                        Text("5 秒").tag(TimeInterval(5))
                        Text("15 秒").tag(TimeInterval(15))
                        Text("30 秒").tag(TimeInterval(30))
                        Text("60 秒").tag(TimeInterval(60))
                    }
                    Picker("涨跌颜色", selection: $settings.redUp) {
                        Text("红涨绿跌").tag(true)
                        Text("绿涨红跌").tag(false)
                    }
                }

                Section {
                    ForEach(appState.providerDescriptors, id: \.id) { descriptor in
                        ProviderRow(descriptor: descriptor)
                    }
                } header: {
                    Text("数据源")
                } footer: {
                    if appState.providerDescriptors.allSatisfy({ !appState.isProviderEnabled($0.id) }) {
                        Text("⚠️ 所有数据源均已关闭，行情和搜索将不可用")
                            .foregroundStyle(.orange)
                    } else {
                        Text("多数据源自动路由：按能力与市场选择，故障时自动降级。未来支持添加自定义数据源。")
                    }
                }

                Section("通用") {
                    Toggle("开机自启", isOn: $settings.launchAtLogin)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text("Pulse 0.1 · 数据来自 Yahoo Finance / 腾讯行情，仅供参考")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
