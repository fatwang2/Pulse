QMLLINT := /usr/lib/qt6/bin/qmllint
QML_FILES := Panel.qml QuoteFeed.qml Watchlist.qml SymbolSearch.qml CandleStore.qml ThemePalette.qml \
	components/ListTabs.qml \
	components/SearchView.qml \
	components/IntradayChart.qml \
	components/CandleChart.qml \
	components/PulseLogo.qml \
	components/StatusDot.qml \
	components/MarketBadge.qml \
	components/Sparkline.qml \
	components/WatchlistRow.qml \
	components/WatchlistView.qml \
	components/SymbolDetail.qml \
	components/SettingsView.qml

.PHONY: test test-js test-source qml-check validate install

test: test-js test-source

test-js:
	node --test tests/test_session_order.js tests/test_market.js tests/test_symbol_id.js tests/test_yahoo_adapter.js tests/test_yahoo_search.js tests/test_model.js tests/test_config.js tests/test_plaintext.js

test-source:
	bash tests/test_panel_source.sh
	bash tests/test_install.sh

qml-check:
	$(QMLLINT) -I /usr/share/omarchy/shell $(QML_FILES)

validate: test qml-check
	omarchy plugin validate .
	git diff --check

install:
	./install.sh
