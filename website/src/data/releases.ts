export type Release = {
  version: string;
  date: string;
  kind: "release" | "improvement" | "fix";
  highlights: {
    zh: readonly string[];
    en: readonly string[];
    ja: readonly string[];
  };
};

export const releases: readonly Release[] = [
  {
    version: "0.11.1",
    date: "2026-08-09",
    kind: "improvement",
    highlights: {
      zh: [
        "Pulse 启用全新品牌图标：保留原有行情波形，以深海军蓝背景、清晰白色轨迹和代表实时更新的蓝色尾段重新设计。",
        "App 图标、菜单栏、弹窗标题、图表加载动画与行情分享图现在使用同一套波形语言，品牌体验更加一致。",
        "优化自选列表的左右对齐：行情行与顶部操作区、底部推送状态共用外层边线，同时保留名称、图表和价格所需的行内留白。",
      ],
      en: [
        "Pulse has a new visual identity built around its original market waveform, redesigned with a deep navy field, a crisp white trace, and a blue live tail for prices updating in real time.",
        "The app icon, menu bar, popover header, chart loading state, and exported market snapshots now use the same waveform language throughout.",
        "Watchlist rows now share the header and streaming status alignment rails while keeping comfortable spacing around names, charts, and prices.",
      ],
      ja: [
        "Pulse のブランドアイコンを刷新しました。従来の相場波形を残しつつ、深いネイビーの背景、明瞭な白いライン、リアルタイム更新を表す青い末尾で再設計しています。",
        "アプリアイコン、メニューバー、ポップオーバーのヘッダー、チャートの読み込み表示、相場共有画像で同じ波形デザインを使用し、ブランド表現を統一しました。",
        "ウォッチリストの左右配置を調整しました。ヘッダーと配信ステータスの外側ラインに揃えながら、銘柄名・チャート・価格の内側余白は維持しています。",
      ],
    },
  },
  {
    version: "0.11.0",
    date: "2026-08-07",
    kind: "release",
    highlights: {
      zh: [
        "新增日文界面：可在设置 → 通用 → 语言中选择「日本語」，也可跟随系统语言。全部界面、菜单、错误提示与分享文案均已本地化，采用日本券商习惯的术语（騰落率、評価損益、前日終値、日足／週足／月足）。",
        "自选列表支持按市场开盘时段自动分块排序：北京时间 8:00–17:00 为港股 → A 股 → 美股，17:00–8:00 为美股 → 港股 → A 股；置顶仅在各自市场块内生效，数字货币始终排在最后。可在设置 → 行情 → 按市场时段排序中关闭。",
        "英文文案校订：几处徽标改为标题式大小写，个别标签的措辞与应用其余部分保持一致。",
      ],
      en: [
        "Japanese is now a full app language, selectable in Settings → General → Language or inherited from your Mac. Every screen, menu, error, and share label speaks it, using the terms Japanese brokerage apps use: 騰落率, 評価損益, 前日終値, 日足/週足/月足.",
        "The watchlist can order itself by which markets are open. Beijing time 8:00–17:00 runs Hong Kong → China A → US; 17:00–8:00 runs US → HK → China A. Symbols stay grouped by market, pins hold their place inside each market, and crypto stays last. Turn it off in Settings → Market → Order by Market Hours.",
        "The English copy got a pass: badges that read as lowercase fragments are title case now, and a few labels read the way the rest of the app does.",
      ],
      ja: [
        "日本語に対応しました。設定 → 一般 → 言語で「日本語」を選ぶか、Mac のシステム言語をそのまま引き継げます。すべての画面・メニュー・エラー・共有ラベルが日本語になり、騰落率・評価損益・前日終値・日足／週足／月足など、日本の証券アプリで使われる用語を採用しています。",
        "ウォッチリストが取引時間に応じて自動で並び替わります。北京時間 8:00–17:00 は香港株 → 中国A株 → 米国株、17:00–8:00 は米国株 → 香港株 → 中国A株の順。銘柄は市場ごとにまとまり、ピン留めは各市場内で維持され、暗号資産は常に最後です。設定 → マーケット → 取引時間で並べ替え からオフにできます。",
        "英語表記を見直しました。小文字の断片に見えていたバッジをタイトルケースに揃え、いくつかのラベルの言い回しをアプリ全体のトーンに合わせています。",
      ],
    },
  },
  {
    version: "0.10.2",
    date: "2026-08-05",
    kind: "improvement",
    highlights: {
      zh: [
        "标的详情页新增公司简介：行情右上角的“简介”入口可查看公司业务介绍与所属行业，内容为英文，当天缓存，仅在打开时请求。",
        "当日盈亏改为按每股当天的真实成本计算：当天买入的份额以成交价为基准而非昨收，当天开仓不再被计入建仓前的涨跌；当天卖出的已实现部分同样计入，收益率以当天真实投入的资金为分母。",
        "清仓不再等同于从未持有：标的详情页与持仓页都会保留已实现收益与交易记录，不再退回“未录入持仓”的引导状态。",
        "切换图表周期不再先闪“暂无数据”：已加载过的周期从缓存即刻重绘，“暂无数据”仅在数据源明确返回空时出现；等待期间显示 Pulse 的脉冲波形动画。",
        "交易记录的删除改到行右键菜单，不再有鼠标移入时替换掉成交金额的悬浮按钮。",
      ],
      en: [
        "Symbol pages now describe the business behind the ticker. An About link in the quote's corner opens the company summary with its sector and industry, in English, cached for the day and only fetched when opened.",
        "Day P&L is measured from what each share actually cost today. Shares bought during the session are measured from their trade price rather than the previous close, shares sold today keep the result the sale realized, and the day's return is measured against the capital actually exposed.",
        "Selling out no longer looks like never having held. The symbol page and the position hub keep the realized result and the trade log instead of falling back to the prompt for a first trade.",
        "Switching chart resolution no longer flashes No data before the new bars arrive. A resolution already loaded once repaints from cache immediately, and the wait is filled by Pulse's own pulse trace.",
        "Deleting a trade moved to the row's context menu, replacing a hover button that displaced the row's amount as the pointer passed over it.",
      ],
      ja: [
        "銘柄詳細ページに会社概要を追加：右上の「概要」から事業内容とセクター・業種を確認できます。内容は英語で、その日はキャッシュされ、開いたときだけ取得します。",
        "当日損益を各株の当日の実コストで計算するように変更：当日買った分は前日終値ではなく約定価格を基準にし、当日の新規建てが建玉前の値動きに含まれなくなりました。当日売却で実現した分も計上され、収益率は当日実際に投入した資金を分母とします。",
        "全株売却してもゼロからのスタート扱いにはなりません：銘柄詳細と保有ハブに実現損益と取引履歴が残り、「保有未登録」の初期案内には戻りません。",
        "チャートの足種を切り替えても「データなし」が先に点滅しなくなりました：一度読み込んだ足種はキャッシュから即座に再描画し、「データなし」はデータソースが明確に空を返したときだけ表示。待機中は Pulse のパルス波形アニメーションを表示します。",
        "取引の削除は行の右クリックメニューに移動し、ポインタを乗せると約定金額を隠すホバーボタンを廃止しました。",
      ],
    },
  },
  {
    version: "0.10.1",
    date: "2026-08-03",
    kind: "fix",
    highlights: {
      zh: [
        "修复 Longbridge 在盘前、盘后或夜盘无成交时把 0 误作真实价格的问题：Pulse 现在跨时段按时间选取最近一次有效成交，不再出现错误的 0 价格与 -100% 涨跌幅。",
        "扩展时段的行情统计继续展示最近一个完整常规交易日的今开、最高、最低、成交量与成交额，不再被盘前、盘后或夜盘推送覆盖。",
        "自选标的右键菜单新增“从当前列表中删除”；移除后所属列表立即同步，仍属于其他列表的标的与持仓继续保留。",
      ],
      en: [
        "Fixed Longbridge empty-session zeroes being treated as real pre-market, post-market, or overnight prices. Pulse now selects the latest valid trade across sessions, preventing false 0 prices and -100% changes.",
        "During extended hours, market statistics continue to show the latest completed regular session's open, high, low, volume, and turnover instead of being overwritten by extended-session pushes.",
        "The watchlist context menu now includes a direct Remove from Current List action. Membership updates immediately, while symbols and positions remain available in any other lists they belong to.",
      ],
      ja: [
        "プレ・アフター・夜間に約定がないとき、Longbridge の 0 を実際の価格として扱ってしまう問題を修正。Pulse はセッションをまたいで最新の有効な約定を選ぶため、誤った 0 価格や -100% の騰落率は表示されません。",
        "時間外の間も、マーケット統計は直近の完了した通常セッションの始値・高値・安値・出来高・売買代金を表示し続け、時間外の配信で上書きされなくなりました。",
        "ウォッチリストの右クリックメニューに「現在のリストから削除」を追加。所属リストは即座に反映され、他のリストに属する銘柄と保有はそのまま残ります。",
      ],
    },
  },
  {
    version: "0.10.0",
    date: "2026-08-03",
    kind: "release",
    highlights: {
      zh: [
        "新增“复制为文本”：自选列表和详情页可复制固定英文的结构化市场快照，包含标的信息、报价、来源、时间戳与交易时段；详情页同时附带当前图表的 OHLCV 数据，可直接交给大模型分析。",
        "自选排序升级：每个分组可独立置顶标的，原生拖拽跨越置顶边界会自动置顶或取消置顶；取消置顶会恢复原自定义位置，新加入标的进入非置顶区顶部。",
        "优化跨市场搜索排序：精确匹配的币种或交易对仍优先；其余情况下，股票、ETF 与指数不再被弱相关的加密结果挤到后面。",
        "Longbridge 连接错误现在保留并展示服务端原始信息，更准确地区分网络与授权问题；授权失效时可原地重新授权，旧凭据会保留到新授权验证成功。",
      ],
      en: [
        "Copy as Text exports an English, structured market snapshot from a watchlist or detail page, including instrument metadata, quotes, source, timestamp, and session fields; detail exports also include chart OHLCV data ready for analysis in an LLM.",
        "Watchlist ordering gains group-specific pinning and native drag reordering. Crossing the pinned boundary automatically pins or unpins, unpinning restores the prior custom position, and newly added symbols lead the regular section.",
        "Cross-market search keeps exact crypto base or pair matches first while placing securities ahead of unrelated crypto results.",
        "Longbridge failures now preserve and display the server's original error, classify network and authorization failures more accurately, and offer safe in-place re-authorization without discarding the previous grant before validation.",
      ],
      ja: [
        "「テキストとしてコピー」を追加：ウォッチリストと詳細ページから、銘柄情報・価格・データソース・タイムスタンプ・セッションを含む英語の構造化スナップショットをコピーできます。詳細ページではチャートの OHLCV データも付属し、そのまま LLM に渡して分析できます。",
        "ウォッチリストの並べ替えを強化：リストごとに銘柄をピン留めでき、ドラッグでピン留め境界をまたぐと自動でピン留め・解除。解除すると元のカスタム位置に戻り、新規追加の銘柄は通常セクションの先頭に入ります。",
        "クロスマーケット検索の順位を改善：暗号資産の完全一致は引き続き最優先。それ以外では、株式・ETF・指数が関連の薄い暗号資産の結果に押し下げられなくなりました。",
        "Longbridge のエラーはサーバーの元のメッセージを保持して表示し、ネットワークと認証の問題をより正確に区別。認証が失効してもその場で再認証でき、新しい認証が検証されるまで既存の資格情報は保持されます。",
      ],
    },
  },
  {
    version: "0.9.0",
    date: "2026-07-31",
    kind: "release",
    highlights: {
      zh: [
        "交易记录上线：买入卖出以交易账本重放，自动推导持仓数量、移动平均成本与已实现盈亏；持仓页升级为中心页，含月度交易日志与快捷校准。",
        "支持空单：先卖后买即开空，空头均价按入场价加权，买入回补自动结算盈亏，穿越翻仓按成交价换边；空头数量以负数直观呈现。",
        "非盘中时段，详情页在盘前、盘后或夜盘价旁边同时展示上一个盘中的收盘价与当日涨跌幅。",
        "指数（纳指、标普等）不再显示盘前盘后翼区、时段底色与标签——指数只在常规时段计算。",
        "自选列表趋势线固定展示盘中时段，盘前盘后开关仅作用于详情页图表。",
        "右键菜单改为原生多选分组（取消勾选即移除）并新增调整顺序入口；持仓摘要与交易记录标题可直接进入对应页面。",
      ],
      en: [
        "Position trades: buys and sells replay into a transaction ledger deriving quantity, moving-average cost, and realized P&L, with a position hub, monthly trade log, and quick-set calibration.",
        "Short positions: sell first to open a short, buy back to cover and realize P&L, with trades crossing zero flipping sides at the trade price. Short quantities display as negatives.",
        "Outside regular hours, the detail page shows the last regular close and its own day change next to the live pre-market, post-market, or overnight price.",
        "Indices no longer draw pre/post wings, session shading, or session labels — they compute during regular hours only.",
        "Watchlist trend lines always frame the regular session; the extended-hours setting applies to the detail chart only.",
        "The context menu gains native multi-select group membership and a reorder entry, and position summaries navigate straight into their pages.",
      ],
      ja: [
        "取引記録が登場：買い・売りを取引台帳としてリプレイし、保有数量・移動平均取得単価・実現損益を自動で算出。保有ページはハブに進化し、月別の取引ログとクイック調整を備えます。",
        "空売りに対応：先に売れば空売りの建玉になり、空売りの平均単価は建値で加重。買い戻しで損益を自動確定し、ゼロをまたぐ取引は約定価格でサイドを反転。空売りの数量は負数で直感的に表示されます。",
        "取引時間外は、詳細ページにプレ・アフター・夜間の価格と並べて、直近の通常セッションの終値とその日の騰落率を表示します。",
        "指数（ナスダック、S&P など）ではプレ・アフターの帯やセッションの背景・ラベルを表示しません——指数は通常セッションのみで計算されます。",
        "ウォッチリストのトレンドラインは常に通常セッションを表示し、時間外設定は詳細チャートにのみ適用されます。",
        "右クリックメニューはネイティブの複数リスト選択（チェックを外すと削除）になり、並べ替えの入口を追加。保有サマリーと取引履歴のタイトルから対応ページへ直接移動できます。",
      ],
    },
  },
  {
    version: "0.8.1",
    date: "2026-07-30",
    kind: "improvement",
    highlights: {
      zh: [
        "自选列表与分享卡片的趋势线现在跟随延长时段设置：盘前、盘后以灰色翼区呈现，并在 9:30 / 16:00 边界加上细分隔线，与详情页分时图保持一致。",
        "修复盘前时段趋势线被压缩到图表尾部的问题：当延长时段数据挤占最新分页时，Longbridge 分钟历史会自动补拉上一交易日的盘中数据。",
        "分享 K 线图现在生成真正的蜡烛图卡片，内容与屏幕上缩放到的区间完全一致，包含成交量、时段底色和交易所时区的起止时间。",
      ],
      en: [
        "Watchlist and share-card trend lines now follow the extended-hours setting, drawing pre/post sessions as gray wings with hairline separators at the 9:30 / 16:00 boundaries to match the detail chart.",
        "Fixed pre-market trend lines collapsing into the tail of the chart: Longbridge minute history now backfills the prior regular session when extended-hours rows crowd it out of the latest page.",
        "Sharing a K-line chart now produces a true candlestick card of exactly the visible zoom window, including volume, session tinting, and the window's range in exchange time.",
      ],
      ja: [
        "ウォッチリストと共有カードのトレンドラインが時間外設定に従うようになりました：プレ・アフターはグレーの帯で描画され、9:30 / 16:00 の境界に細い区切り線が入り、詳細ページの日中チャートと一致します。",
        "プレマーケットのトレンドラインがチャート末尾に押し込まれる問題を修正：時間外データが最新ページを圧迫する場合、Longbridge の分足履歴が前営業日の通常セッションを自動で補完します。",
        "ローソク足チャートの共有は、画面でズームした範囲そのままの本物のローソク足カードを生成します。出来高、セッションの背景色、取引所時間での期間も含まれます。",
      ],
    },
  },
  {
    version: "0.8.0",
    date: "2026-07-30",
    kind: "release",
    highlights: {
      zh: [
        "K 线图升级为标准蜡烛图，成交量与蜡烛严格对齐，并支持鼠标滚轮、触控板缩放和横向浏览。",
        "新增 5 分、15 分、30 分和 1 小时 K 线，可通过紧凑的分段按钮与下拉菜单切换，均配有成交量。",
        "美股分时图默认展示 04:00–20:00 的盘前与盘后行情，也可在设置中关闭。",
        "Longbridge 分钟历史会在需要时自动向前补页，补齐更早的盘前数据；补页失败时仍保留最新行情。",
        "周 K 悬停卡显示完整交易周区间，并优化了图表标签、悬停性能和搜索输入体验。",
      ],
      en: [
        "K-line charts now use true candlesticks with precisely aligned volume, mouse-wheel and trackpad zoom, and horizontal browsing.",
        "Added 5-minute, 15-minute, 30-minute, and 1-hour K-lines with volume, selected through a compact split control.",
        "US intraday charts show pre-market and post-market trading from 04:00 to 20:00 ET by default, with a Settings toggle.",
        "Longbridge minute history pages backward when needed to recover earlier pre-market data while preserving the latest page if backfill fails.",
        "Weekly hover cards show the full trading-week range, alongside refined chart labels, hover performance, and search focus.",
      ],
      ja: [
        "チャートが標準的なローソク足になりました。出来高はローソクと正確に揃い、マウスホイールやトラックパッドでのズーム、横方向のスクロールに対応します。",
        "5分・15分・30分・1時間足を追加。コンパクトなセグメントボタンとメニューで切り替えられ、いずれも出来高付きです。",
        "米国株の日中チャートは、米東部時間 04:00–20:00 のプレ・アフターをデフォルトで表示します。設定でオフにもできます。",
        "Longbridge の分足履歴は必要に応じて自動で過去方向にページを補完し、より早いプレマーケットのデータを取得。補完に失敗しても最新のデータは保持されます。",
        "週足のホバーカードは取引週全体の期間を表示。チャートのラベル、ホバー時のパフォーマンス、検索入力の体験も改善しました。",
      ],
    },
  },
  {
    version: "0.7.0",
    date: "2026-07-29",
    kind: "release",
    highlights: {
      zh: [
        "全新社交分享卡：自选卡改为 1:1 画布、以当前分组命名，列表再长也完整收录并自动延长。",
        "个股分享卡改为 16:9 海报式布局，趋势图通栏展示，新增日内区间条。",
        "分享卡跟随系统深浅色外观与红涨绿跌设置，底部品牌栏替换了免责声明。",
        "搜索移入工具栏：点击放大镜或按 ⌘F 唤起即聚焦，空态提供可清除的最近搜索与热门标的。",
        "搜索结果可直接打开行情详情页，未关注的标的也能查看并从详情页添加。",
        "A 股与港股分时图跨越午休连续绘制，不再断开。",
      ],
      en: [
        "Redesigned share cards: the watchlist card is a 1:1 canvas titled after the selected list, including every symbol and growing with long lists.",
        "The symbol share card moves to a 16:9 poster layout with a full-bleed trend chart and a day-range bar.",
        "Share cards follow the system appearance and your rise/fall color setting, with a brand footer replacing the disclaimer.",
        "Search moved into the toolbar: the magnifier or ⌘F opens a focused panel with clearable recent searches and popular symbols.",
        "Search results open the full quote page — including symbols you don't watch — and can be added from there.",
        "A-share and Hong Kong intraday charts draw continuously across the lunch break.",
      ],
      ja: [
        "共有カードを一新：ウォッチリストのカードは 1:1 キャンバスになり、選択中のリスト名がタイトルに。長いリストもすべての銘柄を収め、自動で伸びます。",
        "銘柄の共有カードは 16:9 のポスターレイアウトになり、トレンドチャートを全幅で表示し、当日レンジバーを追加しました。",
        "共有カードはシステムの外観モードと騰落カラー設定に従い、フッターのブランド表示が免責事項に代わりました。",
        "検索をツールバーに移動：虫めがねのクリックか ⌘F でフォーカス付きのパネルが開き、空の状態では消去可能な検索履歴と人気の銘柄を表示します。",
        "検索結果から直接、詳細ページを開けます——ウォッチしていない銘柄も閲覧でき、そこから追加できます。",
        "中国A株と香港株の日中チャートは、昼休みをまたいで途切れずに描画されます。",
      ],
    },
  },
  {
    version: "0.6.3",
    date: "2026-07-27",
    kind: "fix",
    highlights: {
      zh: [
        "Longbridge 现在按官方 SDK 实际协商的行情包和时间戳区分实时与延迟行情。",
        "延迟的 Longbridge 行情会让位于更及时的备用来源，详情页始终显示实际来源和延迟。",
        "OAuth 身份不再随 Mac 的地区或时区变化；现有登录保持有效，受影响用户可在设置中刷新授权。",
      ],
      en: [
        "Longbridge quotes now use the official SDK's negotiated package and timestamp to distinguish real-time from delayed data.",
        "Delayed Longbridge data yields to a fresher fallback when available, while details always show the actual source and delay.",
        "OAuth identity no longer changes with the Mac's region or time zone; existing sessions remain valid and affected users can refresh authorization in Settings.",
      ],
      ja: [
        "Longbridge は公式 SDK が実際に交渉した価格パッケージとタイムスタンプに基づいて、リアルタイムと遅延データを区別するようになりました。",
        "遅延した Longbridge のデータは、より新しい代替ソースがあればそちらに譲ります。詳細ページには常に実際のソースと遅延が表示されます。",
        "OAuth の識別子が Mac の地域やタイムゾーンで変わらなくなりました。既存のログインは有効なままで、影響を受けた場合は設定から認証を更新できます。",
      ],
    },
  },
  {
    version: "0.6.2",
    date: "2026-07-24",
    kind: "fix",
    highlights: {
      zh: [
        "自选分组现在可以从右键菜单直接删除，不再弹出会关闭菜单栏面板的确认窗口。",
        "删除分组时，独有标的会安全移入其他分组，持仓数据不会丢失。",
      ],
      en: [
        "Delete a watchlist directly from its context menu, without a confirmation window that closes the menu bar panel.",
        "Symbols unique to that list move safely to another list, with position data preserved.",
      ],
      ja: [
        "ウォッチリストを右クリックメニューから直接削除できるようになりました。メニューバーのパネルを閉じてしまう確認ウィンドウは表示されません。",
        "リストを削除すると、そのリストだけに属していた銘柄は安全に別のリストへ移動し、保有データは失われません。",
      ],
    },
  },
  {
    version: "0.6.1",
    date: "2026-07-24",
    kind: "fix",
    highlights: {
      zh: [
        "修复自动更新版本号，使 0.5.1 可以正确发现并安装 0.6 系列更新。",
        "包含 0.6.0 中的 Longbridge SDK、指数规范化、稳定名称与设置持久化改进。",
      ],
      en: [
        "Fixed automatic update versioning so Pulse 0.5.1 can discover and install the 0.6 series.",
        "Includes the Longbridge SDK, normalized indices, stable names, and persistent settings introduced in 0.6.0.",
      ],
      ja: [
        "自動アップデートのバージョン番号を修正し、Pulse 0.5.1 が 0.6 系のアップデートを正しく検出・インストールできるようになりました。",
        "0.6.0 で導入した Longbridge SDK、指数の正規化、安定した銘柄名、設定の永続化の改善を含みます。",
      ],
    },
  },
  {
    version: "0.6.0",
    date: "2026-07-24",
    kind: "release",
    highlights: {
      zh: [
        "Longbridge 行情切换到固定版本的官方 SDK，并加强断线恢复与单标的回退。",
        "统一不同 Provider 下的指数身份、名称、搜索标签与代码映射。",
        "指数按不可交易基准处理，不再显示持仓编辑入口。",
        "标的名称遵循行情源优先级：降级不改名，更高优先级来源可以更新名称。",
        "红涨绿跌、列表指标等显示偏好现在会在重启后保留。",
        "长自选列表支持滚动，截断的标的名称可通过系统浮层查看完整内容。",
      ],
      en: [
        "Moved Longbridge market data to the pinned official SDK, with stronger recovery and per-symbol fallback.",
        "Normalized index identity, names, search labels, and symbol mapping across providers.",
        "Indices are treated as non-tradable benchmarks and no longer show position editing.",
        "Security names now follow quote-provider priority: fallback cannot downgrade them, while a higher-priority source can improve them.",
        "Display preferences such as rise/fall colors and watchlist metrics now survive restarts.",
        "Long watchlists scroll cleanly, and truncated names reveal their full value in a native tooltip.",
      ],
      ja: [
        "Longbridge の価格データをバージョン固定の公式 SDK に移行し、切断からの復帰と銘柄単位のフォールバックを強化しました。",
        "データソース間で指数の識別・名称・検索ラベル・コードのマッピングを統一しました。",
        "指数は取引できないベンチマークとして扱われ、保有の編集は表示されなくなりました。",
        "銘柄名はデータソースの優先度に従います：フォールバックで名称は劣化せず、より優先度の高いソースだけが更新できます。",
        "騰落カラーやリストの指標などの表示設定が、再起動後も保持されるようになりました。",
        "長いウォッチリストもスムーズにスクロールでき、省略された銘柄名はネイティブのツールチップで全文を確認できます。",
      ],
    },
  },
  {
    version: "0.5.1",
    date: "2026-07-21",
    kind: "fix",
    highlights: {
      zh: [
        "搜索结果会在任一有效数据源返回后立即出现，不再等待所有来源。",
        "搜索加入超时边界；快速输入时会取消旧请求，临时空结果也不再被缓存。",
      ],
      en: [
        "Search results now appear as soon as any useful source responds, without waiting for every provider.",
        "Searches now have a deadline, superseded requests cancel cleanly, and transient empty results are no longer cached.",
      ],
      ja: [
        "検索結果は、いずれかの有効なデータソースが応答した時点ですぐに表示され、すべてのソースを待たなくなりました。",
        "検索にタイムアウトを設定。速い入力では古いリクエストがきれいにキャンセルされ、一時的な空の結果もキャッシュされなくなりました。",
      ],
    },
  },
  {
    version: "0.5.0",
    date: "2026-07-21",
    kind: "release",
    highlights: {
      zh: [
        "新增多个命名自选分组，可创建、重命名、删除、拖拽排序，并用 Command-1 至 Command-9 快速切换。",
        "搜索改为并发查询数据源，结果会加入当前分组；同一标的可以出现在多个分组中。",
        "菜单栏轮播可以指定某个自选分组。",
        "Longbridge 重连与授权迁移更可靠，并提供清晰的连接、降级状态与重试入口。",
        "分享图片加入低调的 pulseticker.app 标识，并修正不同市场的成交额显示。",
      ],
      en: [
        "Added multiple named watchlists with create, rename, delete, drag reordering, and Command-1 through Command-9 shortcuts.",
        "Search now runs providers concurrently and adds results to the selected list; a symbol can belong to multiple lists.",
        "Menu bar quote rotation can target a specific watchlist.",
        "Longbridge reconnect and authorization migration are more reliable, with clearer status and retry controls.",
        "Share images now carry a quiet pulseticker.app signature, alongside corrected turnover values across markets.",
      ],
      ja: [
        "名前付きウォッチリストを複数作成できるようになりました。作成・名前変更・削除・ドラッグでの並べ替えに対応し、Command-1〜9 で素早く切り替えられます。",
        "検索はデータソースへ並行して問い合わせ、結果は選択中のリストに追加されます。同じ銘柄を複数のリストに入れられます。",
        "メニューバーのローテーションを特定のウォッチリストに絞れます。",
        "Longbridge の再接続と認証の移行がより確実になり、接続・フォールバックの状態表示と再試行の操作が明確になりました。",
        "共有画像にさりげない pulseticker.app のロゴが入り、各市場の売買代金の表示も修正しました。",
      ],
    },
  },
  {
    version: "0.4.1",
    date: "2026-07-20",
    kind: "improvement",
    highlights: {
      zh: [
        "应用内新增 Pulse 官网与 GitHub 的快捷入口。",
        "设置、搜索结果与 Longbridge 连接反馈过渡更顺滑，并遵循“减弱动态效果”设置。",
        "官网提供稳定的最新版下载地址，并展示 Pulse 使用的行情数据来源。",
      ],
      en: [
        "Added direct links to the Pulse website and GitHub from inside the app.",
        "Smoothed settings, search, and Longbridge connection transitions while respecting Reduce Motion.",
        "The website now offers a stable latest-download URL and identifies the market-data sources Pulse uses.",
      ],
      ja: [
        "アプリ内に Pulse 公式サイトと GitHub へのショートカットを追加しました。",
        "設定・検索結果・Longbridge 接続のトランジションがより滑らかになり、「視差効果を減らす」設定に従います。",
        "公式サイトに常に最新版を指すダウンロード URL を用意し、Pulse が使用するマーケットデータの提供元を掲載しました。",
      ],
    },
  },
  {
    version: "0.4.0",
    date: "2026-07-15",
    kind: "release",
    highlights: {
      zh: [
        "加密货币搜索、行情与图表切换到 Binance Spot 公共接口，并在面板打开时接收秒级 WebSocket 更新。",
        "加密货币统一使用 BTC/USDT 这类基础币/计价币格式，旧标的会自动迁移。",
        "Binance 与 Longbridge 实时流可以同时运行，各自服务加密货币与证券行情。",
        "数据源设置使用统一的状态和市场覆盖说明。",
        "新增可随时关闭的匿名使用统计，且不会上传标的、自选、持仓、搜索或凭证。",
      ],
      en: [
        "Moved crypto search, quotes, and charts to Binance Spot public APIs, with one-second WebSocket updates while the panel is open.",
        "Standardized crypto symbols as base/quote pairs such as BTC/USDT, with automatic migration.",
        "Binance and Longbridge streams can run together for crypto and securities.",
        "Unified status and market-coverage descriptions across data-source settings.",
        "Added optional anonymous product analytics that never includes symbols, watchlists, positions, searches, or credentials.",
      ],
      ja: [
        "暗号資産の検索・価格・チャートを Binance Spot の公開 API に移行し、パネルを開いている間は秒単位の WebSocket 更新を受信します。",
        "暗号資産のシンボルを BTC/USDT のような基軸通貨/決済通貨ペアに統一し、既存の銘柄は自動で移行されます。",
        "Binance と Longbridge のリアルタイムストリームは同時に動作し、それぞれ暗号資産と証券の価格を担当します。",
        "データソース設定の状態表示と市場カバレッジの説明を統一しました。",
        "いつでもオフにできる匿名の利用統計を追加。銘柄・ウォッチリスト・保有・検索内容・認証情報が送信されることはありません。",
      ],
    },
  },
  {
    version: "0.3.0",
    date: "2026-07-15",
    kind: "release",
    highlights: {
      zh: [
        "标的详情页新增分享，可生成不包含私人持仓的行情图片。",
        "自选列表、详情页和分享图片统一使用当前交易时段的一分钟趋势数据。",
        "趋势缓存在列表与详情之间共享，让不同界面尽量保持同一市场快照。",
        "实时行情状态在打开和关闭面板时保持稳定，不再闪回普通状态。",
      ],
      en: [
        "Added symbol sharing from the detail page, with private position data excluded.",
        "Watchlists, details, and shared images now use the same current-session one-minute trend data.",
        "Trend data is shared between list and detail caches to keep surfaces on the same market snapshot.",
        "Live-feed status now stays stable while opening or closing the panel.",
      ],
      ja: [
        "銘柄詳細ページから共有できるようになりました。個人の保有データを含まない価格画像を生成します。",
        "ウォッチリスト・詳細ページ・共有画像は、現在のセッションの 1 分足トレンドデータを共通で使用します。",
        "トレンドのキャッシュをリストと詳細で共有し、各画面ができるだけ同じ市場スナップショットを表示するようにしました。",
        "リアルタイム配信の状態表示が、パネルの開閉時に通常状態へ点滅して戻らなくなりました。",
      ],
    },
  },
  {
    version: "0.2.0",
    date: "2026-07-14",
    kind: "release",
    highlights: {
      zh: [
        "新增 Longbridge 实时行情，可通过浏览器授权或 OpenAPI 密钥连接自己的账户；凭证只保存在本地钥匙串。",
        "支持长连接实时推送，并覆盖美股夜盘的独立状态与价格。",
        "Tencent、Yahoo 与 Longbridge 可以分别设置刷新周期，并只在对应市场开盘时轮询。",
        "重做数据源详情页，清晰展示连接状态、覆盖市场、刷新方式与时效。",
        "自选列表底部开始展示“实时推送”等行情健康状态。",
      ],
      en: [
        "Added Longbridge real-time quotes through browser authorization or OpenAPI keys, with credentials kept in the local Keychain.",
        "Added persistent live streaming, including a dedicated US overnight state and price.",
        "Tencent, Yahoo, and Longbridge now have independent refresh intervals and market-hours-aware polling.",
        "Redesigned source detail pages to explain connection, coverage, refresh mode, and freshness.",
        "The watchlist footer now reports feed health such as “Streaming live.”",
      ],
      ja: [
        "Longbridge のリアルタイム価格に対応。ブラウザ認証または OpenAPI キーで自分のアカウントに接続でき、認証情報はローカルのキーチェーンにのみ保存されます。",
        "常時接続のリアルタイム配信に対応し、米国株の夜間セッションも独立した状態と価格でカバーします。",
        "Tencent・Yahoo・Longbridge はそれぞれ更新間隔を設定でき、対応する市場の取引時間中だけポーリングします。",
        "データソースの詳細ページを刷新し、接続状態・対応市場・更新方法・データの鮮度をわかりやすく表示します。",
        "ウォッチリストの下部に「リアルタイム配信中」などのデータ状態が表示されるようになりました。",
      ],
    },
  },
  {
    version: "0.1.6",
    date: "2026-07-11",
    kind: "improvement",
    highlights: {
      zh: [
        "详情统计用振幅替代成交额，更直观地显示当日高低波动范围。",
        "价格更新加入随涨跌方向滚动的数字动画，页面、按钮与周期切换也更加顺滑。",
        "所有动画遵循 macOS 的“减弱动态效果”设置。",
        "修复详情标题截断，并改善较长本地化文案下的周期选择器布局。",
      ],
      en: [
        "Replaced turnover with amplitude in detail statistics to show the day’s high–low range more clearly.",
        "Added directional rolling digits for price changes and smoother page, button, and period transitions.",
        "All motion now respects the macOS Reduce Motion setting.",
        "Fixed detail-title truncation and improved the period picker for longer localizations.",
      ],
      ja: [
        "詳細統計の売買代金を値幅率に置き換え、その日の高値・安値の変動幅をより直感的に示すようにしました。",
        "価格の更新に騰落方向へ流れる数字のアニメーションを追加し、ページ・ボタン・足種切り替えもより滑らかになりました。",
        "すべてのアニメーションが macOS の「視差効果を減らす」設定に従います。",
        "詳細タイトルの切り詰めを修正し、長いローカライズ文言でも足種セレクタのレイアウトが崩れないよう改善しました。",
      ],
    },
  },
  {
    version: "0.1.5",
    date: "2026-07-10",
    kind: "release",
    highlights: {
      zh: [
        "可以把品牌化、适合手机查看的自选列表图片直接复制到剪贴板。",
        "分享图片会跟随当前列表指标，并根据自选数量自动调整布局。",
        "A 股分时优先使用腾讯实时数据，并以 Yahoo 作为回退和历史 K 线来源。",
        "复制成功提示与市场状态可以同时清晰显示。",
      ],
      en: [
        "Copy a branded, mobile-friendly watchlist image directly to the clipboard.",
        "Share images now follow the selected metric and adapt to watchlist length.",
        "China A-share intraday data now prefers realtime Tencent data, with Yahoo fallback and historical candles.",
        "Copy confirmation now appears without hiding market status.",
      ],
      ja: [
        "ブランド入りでスマートフォンでも見やすいウォッチリスト画像を、そのままクリップボードにコピーできます。",
        "共有画像は選択中のリスト指標に従い、銘柄数に応じてレイアウトを自動調整します。",
        "中国A株の日中データは Tencent のリアルタイムデータを優先し、Yahoo をフォールバックと過去のローソク足に使用します。",
        "コピー完了の通知と市場の状態表示が、同時にはっきり表示されるようになりました。",
      ],
    },
  },
  {
    version: "0.1.4",
    date: "2026-07-09",
    kind: "release",
    highlights: {
      zh: [
        "新增简体中文与英文，支持跟随系统语言或手动切换。",
        "通过 Yahoo Finance 增加加密货币搜索、行情与分时图支持。",
        "为搜索、行情和 K 线加入缓存与请求节流，降低重复请求和限流风险。",
        "搜索输入与加载状态更稳定，行情详情也会分别显示时效、来源与市场时间。",
      ],
      en: [
        "Added English and Simplified Chinese with system-language detection and manual switching.",
        "Added crypto search, quotes, and intraday charts through Yahoo Finance.",
        "Added caching and request pacing for search, quotes, and candles.",
        "Improved search focus and loading states, with separate freshness, source, and market-time metadata.",
      ],
      ja: [
        "簡体字中国語と英語を追加。システム言語の自動検出と手動切り替えに対応しました。",
        "Yahoo Finance 経由で暗号資産の検索・価格・日中チャートに対応しました。",
        "検索・価格・ローソク足にキャッシュとリクエスト調整を追加し、重複リクエストとレート制限のリスクを軽減しました。",
        "検索入力と読み込み状態が安定し、詳細ページには鮮度・データソース・市場時間がそれぞれ表示されます。",
      ],
    },
  },
  {
    version: "0.1.3",
    date: "2026-07-08",
    kind: "improvement",
    highlights: {
      zh: ["加入正式的 Pulse macOS 应用图标。"],
      en: ["Introduced the official Pulse macOS app icon."],
      ja: ["正式な Pulse macOS アプリアイコンを導入しました。"],
    },
  },
  {
    version: "0.1.2",
    date: "2026-07-08",
    kind: "fix",
    highlights: {
      zh: [
        "新增适合首次安装的 DMG 安装包。",
        "修复沙盒环境下的 Sparkle 自动更新支持。",
      ],
      en: [
        "Added a DMG installer for first-time installation.",
        "Fixed Sparkle automatic updates for sandboxed builds.",
      ],
      ja: [
        "初回インストール向けの DMG インストーラを追加しました。",
        "サンドボックス環境での Sparkle 自動アップデートを修正しました。",
      ],
    },
  },
  {
    version: "0.1.1",
    date: "2026-07-08",
    kind: "improvement",
    highlights: {
      zh: [
        "完善首次公开预览的应用截图与安装说明，让菜单栏自选列表更容易被了解。",
      ],
      en: [
        "Refined the first public preview with a clearer menu bar watchlist screenshot and installation guidance.",
      ],
      ja: [
        "初回公開プレビューのスクリーンショットとインストール手順を改善し、メニューバーのウォッチリストをより分かりやすくしました。",
      ],
    },
  },
  {
    version: "0.1.0",
    date: "2026-07-08",
    kind: "release",
    highlights: {
      zh: [
        "Pulse 首次公开发布：在 macOS 菜单栏查看美股、港股、A 股、指数与 ETF。",
        "支持自选列表、菜单栏行情轮播、持仓与盈亏、详情统计、分时图和 K 线。",
        "通过腾讯与 Yahoo Finance 提供行情路由与自动回退。",
        "根据交易时段刷新并在本地保存自选、持仓与设置。",
      ],
      en: [
        "Pulse launched publicly as a macOS menu bar tracker for US, Hong Kong, and China stocks, indices, and ETFs.",
        "Included watchlists, menu bar quote rotation, positions and P&L, detail statistics, intraday charts, and candles.",
        "Added Tencent and Yahoo Finance provider routing with automatic fallback.",
        "Added market-hours-aware refresh and local persistence for watchlists, positions, and settings.",
      ],
      ja: [
        "Pulse が初公開：macOS のメニューバーで米国株・香港株・中国A株・指数・ETF をチェックできます。",
        "ウォッチリスト、メニューバーのローテーション表示、保有と損益、詳細統計、日中チャート、ローソク足を搭載しました。",
        "Tencent と Yahoo Finance によるデータソースのルーティングと自動フォールバックを追加しました。",
        "取引時間に応じた更新と、ウォッチリスト・保有・設定のローカル保存に対応しました。",
      ],
    },
  },
];
