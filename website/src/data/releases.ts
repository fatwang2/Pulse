export type Release = {
  version: string;
  date: string;
  kind: "release" | "improvement" | "fix";
  highlights: {
    zh: readonly string[];
    en: readonly string[];
    ja: readonly string[];
    ko: readonly string[];
  };
};

export const releases: readonly Release[] = [
  {
    version: "0.15.1",
    date: "2026-08-28",
    kind: "fix",
    highlights: {
      zh: [
        "自选可以在原地取舍了：搜索结果里已添加标的的对勾现在可点击，移除后停留在结果页；详情页与固定小窗的自选入口改为星标切换——描边星加入当前分组，实心星移除。",
        "持仓与自选解耦。持仓录入入口对每个可持仓标的长驻显示；从所有分组移除后交易记录照常保留，详情页底部统一为“无记录显示引导、有记录显示记录”。对未自选标的录入持仓不会再把它悄悄加回列表。",
        "分组条尾部的加号改为悬停显示，右键任意分组标签可直接“新建列表”，不再被误认成添加标的的入口（加标的仍走顶部搜索）。",
      ],
      en: [
        "Watchlist membership is editable in place: a watched search result's checkmark now removes it from the current list while staying on the results, and the detail page's watch entry becomes a star toggle — outline star adds to the selected group, filled star removes — mirrored on the pinned window title bar.",
        "Positions are decoupled from the watchlist. The position entry stays visible for every position-eligible instrument, trade records survive removal from every list, and the detail page uniformly shows guidance when there are no records and the records when there are. Recording a position on an unlisted symbol no longer re-adds it to any list.",
        "The plus at the end of the group bar is hover-revealed and “New List” joins the tab context menu, so it no longer reads as the add-symbol entry — search remains the way to add symbols.",
      ],
      ja: [
        "ウォッチリストをその場で編集できるようにしました。検索結果の追加済みチェックマークがクリックで現在のリストから外せます（結果ページはそのまま）。詳細ページのウォッチ入口は星のトグルになり、中空の星でグループに追加、塗りつぶしの星で削除します。ピン留めウィンドウのタイトルバーも同様です。",
        "ポジションをウォッチリストから切り離しました。ポジション入口は対象なら常に表示され、すべてのリストから外しても取引履歴は残り、詳細ページ下部は「記録なし＝ガイド／記録あり＝履歴」に統一されます。未登録銘柄のポジション記録がリストに黙って再追加されることはありません。",
        "グループバー末端のプラスはホバー表示になり、タブの右クリックメニューに「新規リスト」を追加しました。銘柄追加の入口と誤認しにくくなります（銘柄追加は上部の検索から）。",
      ],
      ko: [
        "관심목록을 그 자리에서 편집할 수 있습니다. 검색 결과의 추가됨 체크마크가 클릭으로 현재 목록에서 제거되며(결과 화면 유지), 상세 페이지의 관심 항목은 별 토글로 바뀌어 — 빈 별은 현재 그룹에 추가, 채운 별은 제거 — 고정 창 제목 표시줄에서도 동일하게 동작합니다.",
        "포지션을 관심목록에서 분리했습니다. 포지션 항목은 대상 종목이면 항상 표시되고, 모든 목록에서 제거해도 거래 기록이 유지되며, 상세 페이지 하단은 “기록 없음＝안내 / 기록 있음＝기록”으로 통일됩니다. 미등록 종목의 포지션 기록이 목록에 몰래 다시 추가되지 않습니다.",
        "그룹 바 끝의 플러스는 호버 시 표시되고, 탭 우클릭 메뉴에 “새 목록”이 추가되어 종목 추가 진입점으로 오인되지 않습니다(종목 추가는 상단 검색을 사용합니다).",
      ],
    },
  },
  {
    version: "0.15.0",
    date: "2026-08-26",
    kind: "release",
    highlights: {
      zh: [
        "本机 MCP 智能体接入。在「设置 → 智能体 → MCP」开启后，Pulse 在 127.0.0.1 提供 Streamable HTTP 服务，Bearer 令牌保存在钥匙串。Claude、ChatGPT 以及任何支持 MCP 的客户端，都可以列出自选与持仓、搜索标的、管理分组与标的、记录交易与校准持仓，并调整分组顺序或自定义标的顺序——读写的就是菜单栏里那份实时数据。",
        "设置结构调整：菜单栏与行情展示收进「外观」二级页；MCP 放在独立的「智能体」分区，含连接信息与工具说明。",
      ],
      en: [
        "Local MCP for agents. Turn on Settings → Agents → MCP and Pulse serves Streamable HTTP on your Mac (127.0.0.1 only, Bearer token in the Keychain). Claude, ChatGPT, and any MCP-compatible client can list watchlists and positions, search symbols, manage groups and symbols, record trades and calibrate positions, and reorder groups or custom symbol order — against the same live data you see in the menu bar.",
        "Settings layout for agents: Appearance nests menu bar and market presentation, and MCP sits under a dedicated Agents section with connection fields and a short tools summary.",
      ],
      ja: [
        "ローカル MCP 対応。設定 → エージェント → MCP を有効にすると、Pulse が Mac 上で Streamable HTTP を提供します（127.0.0.1 のみ、Bearer トークンは Keychain）。Claude、ChatGPT、その他 MCP 対応クライアントがウォッチリストや保有の一覧、銘柄検索、グループと銘柄の管理、取引の記録とポジション校正、グループ順・カスタム銘柄順の変更を行えます——メニューバーと同じライブデータです。",
        "設定の構成を整理。メニューバーと相場表示は「外観」の下層へ。MCP は「エージェント」セクションに接続情報とツール概要とともに置きます。",
      ],
      ko: [
        "로컬 MCP 에이전트 지원. 설정 → 에이전트 → MCP를 켜면 Pulse가 Mac에서 Streamable HTTP를 제공합니다(127.0.0.1만, Bearer 토큰은 Keychain). Claude, ChatGPT 및 MCP 지원 클라이언트가 관심목록·보유 조회, 종목 검색, 그룹·종목 관리, 거래 기록과 포지션 보정, 그룹·사용자 지정 종목 순서 변경을 할 수 있습니다 — 메뉴 막대와 같은 실시간 데이터입니다.",
        "설정 구성을 정리했습니다. 메뉴 막대와 시세 표시는 모양 하위 페이지로, MCP는 연결 정보와 도구 요약이 있는 에이전트 섹션에 둡니다.",
      ],
    },
  },
  {
    version: "0.14.1",
    date: "2026-08-25",
    kind: "fix",
    highlights: {
      zh: [
        "报价现在按市场保留应有的小数位：股票与贵金属在需要时显示第三位（例如港股低价股、白银），日股与韩股的整数价不再强行补 `.00`，加密货币大币仍两位、小币保留更高精度。",
        "独立浮窗标题栏里的图钉改为普通工具栏按钮，不再一直亮着 Liquid Glass 选中态，右上角不再比旁边的搜索、分享更抢眼。",
      ],
      en: [
        "Quotes now keep the fraction digits each market needs. Stocks and precious metals can show a third decimal when the print carries one (for example HK penny stocks or silver), Japan and Korea drop trailing `.00` on whole-yen/won prices, and crypto still pads large coins to two places while preserving finer pairs.",
        "In the pinned floating window, the pin control is a plain toolbar button again. It no longer stays lit with Liquid Glass selected chrome, so the top-right corner no longer outweighs search and share beside it.",
      ],
      ja: [
        "価格表示が市場ごとの小数桁に対応しました。株式と貴金属は必要なときに 3 桁目を表示し（香港の低位株や銀など）、日本株・韓国株の整数価格に不要な `.00` を付けなくなり、暗号資産は大型ペアを 2 桁・小型ペアはより細かい桁を保ちます。",
        "ピン留めフローティングウィンドウのタイトルバーのピンを通常のツールバーボタンに戻しました。Liquid Glass の選択状態で常時点灯しなくなり、右上隅が隣の検索・共有より目立たなくなります。",
      ],
      ko: [
        "시세가 시장별로 필요한 소수 자릿수를 유지합니다. 주식과 귀금속은 필요할 때 셋째 자리를 보여 주고(예: 홍콩 저가주, 은), 일본·한국 종목의 정수 가격에는 불필요한 `.00`을 붙이지 않으며, 암호화폐는 큰 쌍은 두 자리·작은 쌍은 더 세밀한 자릿수를 유지합니다.",
        "고정 플로팅 창 제목 표시줄의 핀을 일반 도구 모음 버튼으로 되돌렸습니다. Liquid Glass 선택 상태로 계속 켜져 있지 않아, 오른쪽 위가 옆의 검색·공유보다 눈에 띄지 않습니다.",
      ],
    },
  },
  {
    version: "0.14.0",
    date: "2026-08-24",
    kind: "release",
    highlights: {
      zh: [
        "接入同花顺扶摇（Fuyao）A 股实时行情。在「设置 → 数据源 → 同花顺」填入你自己的 API Key，沪深行情即升级为实时——经盘中实测，API 返回的时间戳与当前时间差不到 1 秒。配置了 Key 后，Pulse 自动将 A 股行情和日 K 路由至同花顺；未配置或触发熔断时，自动回退到现有免费数据源。",
        "统一数据源状态模型。「设置 → 数据源」中 Longbridge 和同花顺现在使用同一套连接状态词汇和重试流程：已连接、连接中、已断开、错误——一键重试会清除熔断状态，但不会动你的凭证。",
      ],
      en: [
        "Fuyao (扶摇), Hithink / Tonghuashun's official A-share data service. Bring your own API key (Settings → Data Sources → 同花顺) to upgrade Shanghai and Shenzhen quotes to real-time — verified live during a trading session, the API returns sub-second-fresh snapshots. Pulse routes A-share quotes and daily candles through Fuyao when a key is present, and falls back to the existing free sources automatically when the key is missing or the circuit breaker trips.",
        "Unified provider status model in Settings. Longbridge and Fuyao now share the same connection-status vocabulary and the same retry flow: connected, connecting, disconnected, or error — with a one-tap retry that clears the circuit breaker without touching credentials.",
      ],
      ja: [
        "同花順扶摇（Fuyao）の A 株リアルタイム行情を統合しました。「設定 → データソース → 同花順」に API キーを入力すると、上海・深圳の行情がリアルタイムにアップグレードされます。取引時間中に実測したところ、API のタイムスタンプと現在時刻の差は 1 秒未満でした。キーが設定されていれば A 株の行情と日足を同花順へルーティングし、未設定やサーキットブレーカ作動時は既存の無料データソースへ自動フォールバックします。",
        "データソースのステータスモデルを統一しました。「設定 → データソース」で Longbridge と同花順が同じ接続ステータス語彙と再試行フローを共有します：接続済み、接続中、切断、エラー——ワンタップ再試行でサーキットブレーカを解除しますが、認証情報には触れません。",
      ],
      ko: [
        "同花順扶摇(Fuyao) A주 실시간 시세를 통합했습니다. 「설정 → 데이터 소스 → 同花順」에 API 키를 입력하면 상하이·선전 시세가 실시간으로 업그레이드됩니다. 장중에 실측한 결과 API 타임스탬프와 현재 시각의 차이는 1초 미만이었습니다. 키가 설정되면 A주 시세와 일봉을 同花順로 라우팅하고, 미설정이나 서킷 브레이커 동작 시에는 기존 무료 데이터 소스로 자동 폴백합니다.",
        "데이터 소스 상태 모델을 통일했습니다. 「설정 → 데이터 소스」에서 Longbridge와 同花順이 동일한 연결 상태 어휘와 재시도 흐름을 공유합니다: 연결됨, 연결 중, 끊김, 오류 — 원탭 재시도로 서킷 브레이커를 해제하지만 인증 정보는 건드리지 않습니다.",
      ],
    },
  },
  {
    version: "0.13.0",
    date: "2026-08-21",
    kind: "release",
    highlights: {
      zh: [
        "全新的首次启动体验：第一次打开 Pulse 会直接展示浮窗，不再只是菜单栏里多出一个图标；App 运行中再次从「应用程序」打开，也会唤出这个窗口。",
        "为新用户准备了一段简短的引导：三步气泡依次带你搜索添加第一只自选、进入详情页、切换日K查看更长周期的走势——每一步都可以自己动手完成，也可以点「下一步」代劳，随时可以跳过。回到列表后还有一条一次性提示，告诉你如何用图钉把窗口收回菜单栏。老用户升级不会看到任何引导。",
        "自选列表为空时的提示语现在是一个真正的按钮，点击直接展开搜索。",
        "安装镜像（DMG）打开后是一个正式的安装界面：品牌背景图，左边是 Pulse，右边是「应用程序」，中间一个箭头。",
      ],
      en: [
        "A first-run welcome: on its very first launch Pulse now presents its floating window instead of only adding an icon to the menu bar, and launching the already-running app from Applications brings that window back.",
        "A short guided tour for new users: three bubbles walk through adding the first symbol via search, opening its detail page, and switching the chart to daily candles — every step can be done by hand or by clicking Next, and the whole tour is skippable. Back on the list, a one-time tip shows how the pin tucks Pulse into the menu bar. Existing installs never see any of it.",
        "The empty watchlist's hint is now an actual button that opens search in place.",
        "The installer disk image opens onto a proper install window: branded background, Pulse on the left, Applications on the right, an arrow in between.",
      ],
      ja: [
        "初回起動の体験を一新しました。初めて Pulse を開くとフローティングウィンドウが表示され、メニューバーにアイコンが増えるだけでは終わりません。起動中に「アプリケーション」からもう一度開いた場合も、このウィンドウが呼び出されます。",
        "新規ユーザー向けの短いガイドツアーを追加しました。3 つの吹き出しが、検索で最初の銘柄を追加し、詳細ページを開き、チャートを日足に切り替えるところまで順に案内します。各ステップは自分で操作しても「次へ」で進めてもよく、いつでもスキップできます。リストに戻ると、ピンでウィンドウをメニューバーへ戻す方法を伝える一度きりのヒントが表示されます。既存ユーザーには一切表示されません。",
        "ウォッチリストが空のときのヒントがボタンになり、クリックするとその場で検索が開きます。",
        "インストーラー（DMG）を開くと、ブランド背景の上で Pulse を Applications へドラッグする正式なインストール画面が表示されます。",
      ],
      ko: [
        "첫 실행 경험을 새로 만들었습니다. Pulse를 처음 열면 플로팅 창이 바로 나타나, 메뉴 막대에 아이콘만 하나 늘어난 채 끝나지 않습니다. 실행 중에 '응용 프로그램'에서 다시 열어도 이 창이 나타납니다.",
        "새 사용자를 위한 짧은 가이드 투어를 추가했습니다. 세 개의 말풍선이 검색으로 첫 종목 추가, 상세 페이지 열기, 차트를 일봉으로 전환하기까지 차례로 안내합니다. 각 단계는 직접 해도 되고 '다음'을 눌러도 되며 언제든 건너뛸 수 있습니다. 목록으로 돌아오면 핀으로 창을 메뉴 막대에 되돌리는 방법을 알려주는 일회성 팁이 나타납니다. 기존 사용자에게는 표시되지 않습니다.",
        "관심 목록이 비어 있을 때의 안내 문구가 실제 버튼이 되어, 클릭하면 바로 검색이 열립니다.",
        "설치 이미지(DMG)를 열면 브랜드 배경 위에서 Pulse를 Applications로 끌어다 놓는 정식 설치 화면이 나타납니다.",
      ],
    },
  },
  {
    version: "0.12.0",
    date: "2026-08-20",
    kind: "release",
    highlights: {
      zh: [
        "新增贵金属品类，共九个标的：伦敦金、伦敦银现货，COMEX 黄金与白银，NYMEX 铂金与钯金，上海黄金交易所的 Au99.99 现货，以及上期所的沪金、沪银期货。上海的标的以人民币计价、按克报价，跟随带夜盘的国内时段；其余以美元计价、按盎司报价。现货一律排在前面——问“黄金多少钱”的人指的就是它。搜“黄金”“现货黄金”“XAU”“GC”乃至“贵金属”都能找到，尽管没有任何数据源的搜索索引覆盖这个品类。",
        "新增日本与韩国股票：东京证券交易所（Prime / Standard / Growth）以及韩国交易所的 KOSPI 与 KOSDAQ 两个板块，并支持日经 225 与韩国综合指数。东京 11:30–12:30 的午休会像港股、A 股一样在分时图上折叠掉；首尔则全天连续交易。韩国的板块归属跟随标的保存，而不是从代码猜——035720 属于 KOSPI，按 KOSDAQ 取到的是完全另一个标的。",
        "新增韩语界面，可在设置 → 通用 → 语言中选择，也会跟随系统语言。用词沿用韩国券商 App 的习惯：등락률、보유 손익、평균 단가、전일 종가、일봉/주봉/월봉。",
        "接入四个新数据源。Naver 提供韩股实时行情与韩文搜索，并且是板块归属的权威来源；新浪财经提供伦敦现货与上期所金属；上海黄金交易所提供 Au99.99 的官方日线；东方财富补上该合约的分时。",
        "标的详情页现在会写明实时数据源的实际请求频率，“实时”和“每 15 秒一次”不再混为一谈。",
        "设置页重新编排：通用移到最上面；匿名使用数据开关移入「数据」分组，与导入导出放在一起——关于数据流出 App 的问题现在都在同一处。",
      ],
      en: [
        "Precious metals: nine instruments across both sides of the market — London spot gold and silver, the COMEX / NYMEX contracts (gold, silver, platinum, palladium), the Shanghai Gold Exchange's Au99.99 spot contract, and the SHFE gold and silver futures. The Shanghai instruments price in CNY per gram on a Chinese session with its own night leg; the rest quote in USD per ounce. Spot leads everywhere, because that is what \"gold\" means to someone asking the price.",
        "Japanese and Korean stocks: Tokyo (Prime, Standard and Growth) plus both Korea Exchange boards, KOSPI and KOSDAQ, with the Nikkei 225 and the KOSPI Composite alongside them. Tokyo's 11:30–12:30 lunch break folds out of the intraday axis the way Hong Kong's and Shanghai's do; Seoul trades straight through. The Korean board is stored with the symbol rather than guessed from the code.",
        "Korean is now a full app language, selectable in Settings → General → Language or inherited from your Mac, using the terms Korean brokerage apps use: 등락률, 보유 손익, 평균 단가, 전일 종가, 일봉/주봉/월봉.",
        "Four new data sources. Naver serves Korean quotes in real time, answers Korean-language search, and is authoritative about which board a code belongs to. Sina carries London spot and SHFE metals, the Shanghai Gold Exchange publishes its own Au99.99 history, and Eastmoney fills that contract's intraday chart.",
        "The symbol detail page now states how often a real-time source is actually polled, so \"real-time\" and \"every 15 seconds\" are no longer the same claim.",
        "Settings reorganized: General moves to the top, and the anonymous usage-data switch joins Import & Export under Data, where the rest of the questions about data leaving the app already live.",
      ],
      ja: [
        "貴金属に対応しました。ロンドン金・銀の現物、COMEX の金・銀、NYMEX のプラチナ・パラジウム、上海黄金交易所の Au99.99 現物、上海期貨交易所の金・銀先物の 9 銘柄です。上海の銘柄は人民元建て・グラム単位で、夜間立会を含む中国のセッションに従います。その他は米ドル建て・オンス単位です。現物を先頭に置いています——「金はいくらか」と尋ねる人が指しているのは現物だからです。",
        "日本株と韓国株に対応しました。東京証券取引所（プライム・スタンダード・グロース）と、韓国取引所の KOSPI・KOSDAQ の両市場、そして日経平均株価と韓国総合株価指数です。東京の 11:30–12:30 の昼休みは、香港や中国A株と同じように日中チャートの軸から畳まれます。ソウルは昼休みなく連続で取引されます。韓国の市場区分はコードから推測せず銘柄と一緒に保存します——035720 は KOSPI であり、KOSDAQ のシンボルはまったく別の銘柄を指します。",
        "韓国語が正式なアプリ言語になりました。設定 → 一般 → 言語で選択するか、Mac の設定を引き継ぎます。韓国の証券アプリで使われる用語（등락률・보유 손익・평균 단가・전일 종가・일봉/주봉/월봉）を採用しています。",
        "データ提供元を 4 つ追加しました。Naver は韓国株をリアルタイムで配信し、韓国語検索に応答し、コードがどちらの市場に属するかについての権威ある情報源です。新浪財経はロンドン現物と上海期貨の金属を、上海黄金交易所は Au99.99 の公式日足を、東方財富はその銘柄の日中チャートを担います。",
        "銘柄詳細画面に、リアルタイム提供元を実際にどの間隔で取得しているかを表示するようになりました。「リアルタイム」と「15 秒ごと」はもう同じ主張ではありません。",
        "設定画面を整理しました。一般を最上部に移し、匿名利用データのスイッチをデータ項目へ移動して、読み込み・書き出しと並べました。アプリからデータが出ていく話が一箇所にまとまります。",
      ],
      ko: [
        "귀금속을 지원합니다. 런던 금·은 현물, COMEX 금·은, NYMEX 백금·팔라듐, 상하이 금거래소의 Au99.99 현물, 상하이선물거래소의 금·은 선물까지 아홉 종목입니다. 상하이 종목은 위안화 기준 그램당 가격으로 야간장이 있는 중국 시간대를 따르고, 나머지는 달러 기준 온스당 가격입니다. 어디서나 현물이 앞에 옵니다. \"금값이 얼마냐\"고 묻는 사람이 가리키는 것이 현물이기 때문입니다.",
        "일본과 한국 주식을 지원합니다. 도쿄증권거래소(프라임·스탠다드·그로스)와 한국거래소의 코스피·코스닥 두 시장, 그리고 닛케이 225와 코스피 지수까지 함께 담았습니다. 도쿄의 11:30–12:30 점심 휴장은 홍콩이나 중국 A주와 마찬가지로 분시 차트 축에서 접힙니다. 서울은 쉬지 않고 이어서 거래됩니다. 한국의 시장 구분은 코드에서 추측하지 않고 종목과 함께 저장합니다. 035720은 코스피이고, 코스닥 심볼로 받으면 전혀 다른 종목이 나옵니다.",
        "한국어가 정식 앱 언어가 되었습니다. 설정 → 일반 → 언어에서 고르거나 Mac 설정을 따릅니다. 등락률, 보유 손익, 평균 단가, 전일 종가, 일봉/주봉/월봉처럼 한국 증권 앱이 쓰는 용어를 씁니다.",
        "데이터 제공처를 네 곳 추가했습니다. 네이버는 한국 주식 시세를 실시간으로 주고 한국어 검색에 답하며, 어떤 코드가 어느 시장에 속하는지에 대한 권위 있는 출처입니다. 시나 파이낸스는 런던 현물과 상하이선물 금속을, 상하이 금거래소는 Au99.99의 공식 일봉을, 동방재부는 그 종목의 분시 차트를 맡습니다.",
        "종목 상세 화면에 실시간 제공처를 실제로 얼마나 자주 조회하는지 표시합니다. 이제 \"실시간\"과 \"15초마다\"는 같은 말이 아닙니다.",
        "설정 화면을 다시 정리했습니다. 일반이 맨 위로 올라가고, 익명 사용 데이터 스위치는 가져오기·내보내기와 함께 데이터 항목으로 옮겼습니다. 앱에서 데이터가 나가는 문제를 한곳에서 봅니다.",
      ],
    },
  },
  {
    version: "0.11.8",
    date: "2026-08-19",
    kind: "improvement",
    highlights: {
      zh: [
        "提升菜单栏面板在复杂桌面背景上的可读性：行情列表、详情和图表现在使用更厚的 macOS 标准材质作为内容背景，同时菜单和操作控件继续保留原生 Liquid Glass 外观。",
      ],
      en: [
        "Improved the legibility of the menu-bar panel on visually busy desktops. Data-dense content now uses a stronger standard macOS material background, while menus and controls retain their native Liquid Glass appearance.",
      ],
      ja: [
        "視覚的に複雑なデスクトップ上でも、メニューバーパネルを読みやすくしました。情報量の多いリスト・詳細・チャートにはより厚みのある macOS 標準マテリアル背景を使用し、メニューと操作コントロールはネイティブの Liquid Glass 表現を維持します。",
      ],
      ko: [
        "복잡한 배경의 데스크톱에서도 메뉴 막대 패널이 잘 읽히도록 개선했습니다. 정보가 빽빽한 목록·상세·차트는 더 두꺼운 macOS 표준 머티리얼을 배경으로 쓰고, 메뉴와 조작 컨트롤은 네이티브 Liquid Glass 표현을 그대로 유지합니다.",
      ],
    },
  },
  {
    version: "0.11.7",
    date: "2026-08-14",
    kind: "fix",
    highlights: {
      zh: [
        "修复自选列表在布局测量文本时因系统字体不可用而崩溃的问题：Pulse 现在会回退到保证存在的系统字体，而不是直接退出。",
        "从自选列表移除的标的，其交易历史现在会被保留；重新添加该标的时会恢复之前的交易记录，而不是从空开始。",
      ],
      en: [
        "Fixed a crash where the watchlist could abort Pulse during layout when the system returned an unavailable font for text measurement. Pulse now falls back to a guaranteed system font instead of crashing.",
        "Trade history for a symbol you remove from the watchlist is now retained, so adding the symbol back restores its previous transactions instead of starting empty.",
      ],
      ja: [
        "ウォッチリストのレイアウト中にシステムが利用できないフォントを返したとき、テキスト計測で Pulse がクラッシュする問題を修正しました。保証されたシステムフォントへフォールバックし、クラッシュしなくなります。",
        "ウォッチリストから削除した銘柄の取引履歴は保持されるようになり、銘柄を再追加すると以前の取引履歴が復元されます（空の状態から始まりません）。",
      ],
      ko: [
        "레이아웃 도중 시스템이 쓸 수 없는 글꼴을 돌려줄 때 텍스트 크기를 재다가 Pulse가 종료되던 문제를 고쳤습니다. 이제는 반드시 존재하는 시스템 글꼴로 물러납니다.",
        "관심목록에서 지운 종목의 거래 기록을 그대로 보관합니다. 그 종목을 다시 추가하면 빈 상태가 아니라 이전 거래가 복원됩니다.",
      ],
    },
  },
  {
    version: "0.11.6",
    date: "2026-08-13",
    kind: "release",
    highlights: {
      zh: [
        "新增独立置顶窗口：可从菜单栏面板将 Pulse 钉在桌面上方，并跨空间保持可见；窗口会记住位置与置顶状态，重新启动或显示器变化后也会恢复到可见区域。",
        "置顶窗口采用原生 macOS 工具栏承载置顶、搜索、分享与更多操作；标的详情、持仓、交易、简介和设置页面的标题与返回导航保持统一对齐。",
        "优化置顶窗口的页面切换与尺寸动画：标题栏和顶部基线不再跳动，窗口高度与页面导航同步变化；菜单栏面板与独立窗口同时打开时也只共用一套实时行情刷新。",
      ],
      en: [
        "Pin Pulse into a standalone floating window that stays above other apps and follows you across Spaces. It remembers its position and pinned state, and safely returns to a visible display after relaunch or monitor changes.",
        "The pinned window uses native macOS toolbar controls for pinning, search, sharing, and more, while quote, position, trade, profile, and settings pages keep their titles and back navigation aligned.",
        "Improved pinned-window navigation and resizing: the title bar and top baseline no longer jump, window height animates in sync with page transitions, and the panel and window share one live market-data refresh session when both are open.",
      ],
      ja: [
        "Pulse をほかのアプリより手前に保ち、すべての操作スペースで表示できる独立フローティングウインドウとして固定できるようになりました。位置と固定状態を記憶し、再起動後やディスプレイ構成の変更後も見える領域へ安全に復元します。",
        "固定ウインドウでは、固定・検索・共有・その他の操作に macOS ネイティブのツールバーを採用しました。銘柄詳細、保有、取引、プロフィール、設定の各ページでも、タイトルと戻るナビゲーションの位置が揃います。",
        "固定ウインドウのページ遷移とサイズ変更を改善しました。タイトルバーや上端の基準線が跳ねず、ウインドウの高さがページ遷移と同期して滑らかに変化します。メニューバーパネルと独立ウインドウを同時に開いても、リアルタイム相場更新は一つのセッションを共有します。",
      ],
      ko: [
        "Pulse를 다른 앱 위에 떠 있는 독립 창으로 고정할 수 있습니다. 여러 스페이스를 오가도 따라오고, 위치와 고정 상태를 기억하며, 다시 실행하거나 모니터 구성이 바뀌어도 보이는 화면 안으로 안전하게 돌아옵니다.",
        "고정 창은 고정·검색·공유 등에 macOS 네이티브 툴바를 씁니다. 시세, 보유, 거래, 종목 정보, 설정 페이지의 제목과 뒤로 가기 위치도 나란히 맞췄습니다.",
        "고정 창의 페이지 전환과 크기 변화를 다듬었습니다. 제목 표시줄과 위쪽 기준선이 튀지 않고 창 높이가 페이지 전환과 함께 움직이며, 메뉴 막대 패널과 독립 창을 함께 열어도 실시간 시세 갱신은 하나만 돌아갑니다.",
      ],
    },
  },
  {
    version: "0.11.5",
    date: "2026-08-12",
    kind: "release",
    highlights: {
      zh: [
        "交易记录现在会显示在日 K 图上：买入与卖出分别以 B/S 标记呈现，同一天同方向的交易会自动聚合；标记避开附近 K 线并通过中性点线关联，悬停可查看加权成交价、数量与金额。",
        "修复 macOS 26 上自选列表可能无法拖动排序的问题：排序期间不再因鼠标经过其他行而重建原生拖放目标，插入指示线和放置操作更加稳定。",
        "修复设置页向上滚动时选项会滑到标题下方并与标题重叠的问题；标题现在固定占据表单上方的独立区域。",
      ],
      en: [
        "Recorded trades now appear on daily candlestick charts as B/S markers. Same-day trades are grouped by side, kept clear of nearby candles, and linked with a neutral dotted guide; hover the day to see weighted price, quantity, and amount.",
        "Fixed watchlist reordering on macOS 26. Moving across rows during a reorder no longer rebuilds the native drop targets, keeping the insertion indicator and drop action reliable.",
        "Fixed Settings options sliding underneath and overlapping the page title while scrolling. The title now stays in its own fixed area above the form.",
      ],
      ja: [
        "取引履歴を日足チャートに B/S マーカーで表示するようになりました。同日の同方向の取引は自動で集約され、近くのローソク足を避けて中立色の点線で関連付けられます。該当日にポインタを合わせると、加重平均価格・数量・金額を確認できます。",
        "macOS 26 でウォッチリストを並べ替えられないことがある問題を修正しました。並べ替え中に他の行を通過してもネイティブのドロップ対象が再構築されず、挿入位置の表示とドロップ操作が安定します。",
        "設定画面を上へスクロールしたとき、項目がタイトルの下に入り込んで重なる問題を修正しました。タイトルはフォーム上部の独立した固定領域に表示されます。",
      ],
      ko: [
        "기록한 거래가 일봉 차트에 B/S 표시로 나타납니다. 같은 날 같은 방향의 거래는 하나로 묶이고, 근처 캔들을 피해 중립색 점선으로 이어집니다. 해당 날짜에 마우스를 올리면 가중 평균가와 수량, 금액을 볼 수 있습니다.",
        "macOS 26에서 관심목록 순서를 바꾸지 못하던 문제를 고쳤습니다. 순서를 바꾸는 동안 다른 행 위를 지나가도 네이티브 드롭 대상이 다시 만들어지지 않아, 삽입 위치 표시와 놓기 동작이 안정적입니다.",
        "설정 화면을 위로 스크롤할 때 항목이 제목 아래로 파고들어 겹치던 문제를 고쳤습니다. 제목은 이제 폼 위쪽 자기 영역에 고정됩니다.",
      ],
    },
  },
  {
    version: "0.11.4",
    date: "2026-08-12",
    kind: "improvement",
    highlights: {
      zh: [
        "新增 Esc 逐层返回：在标的详情、持仓、交易记录、下单和设置子页面按 Esc 即可返回上一层，同时保持 Pulse 菜单栏面板打开；返回与确认按钮的悬停提示也会标明 Esc 和回车键。",
        "修复交易记录右键删除时系统确认框会关闭 Pulse 菜单栏面板、导致无法操作的问题；删除现在与自选列表标签一致，直接从右键菜单执行。",
      ],
      en: [
        "Press Escape on any child page to go back one level while keeping the Pulse menu-bar panel open. Existing button tooltips now disclose Escape and Return without adding permanent interface chrome.",
        "Deleting a trade from the transaction log no longer opens a system confirmation alert that closes the Pulse menu-bar panel. Like watchlist deletion, the destructive context-menu action now deletes immediately.",
      ],
      ja: [
        "銘柄詳細、保有、取引履歴、売買入力、設定の各子ページで Esc を押すと、Pulse のメニューバーパネルを開いたまま一つ前の階層へ戻れるようになりました。戻るボタンと確定ボタンのツールチップにも Esc と Return を表示します。",
        "取引履歴を右クリックして削除すると、システムの確認ダイアログによって Pulse のメニューバーパネルが閉じ、操作できなくなる問題を修正しました。ウォッチリストの削除と同様に、コンテキストメニューから直接削除します。",
      ],
      ko: [
        "하위 페이지 어디서든 Esc를 누르면 Pulse 메뉴 막대 패널을 열어 둔 채 한 단계 뒤로 갑니다. 버튼 툴팁에도 Esc와 Return을 함께 알려 줍니다.",
        "거래 기록을 오른쪽 클릭해 지울 때 시스템 확인 창이 떠서 Pulse 메뉴 막대 패널이 닫히던 문제를 고쳤습니다. 관심목록 삭제와 마찬가지로 컨텍스트 메뉴에서 바로 지웁니다.",
      ],
    },
  },
  {
    version: "0.11.3",
    date: "2026-08-11",
    kind: "fix",
    highlights: {
      zh: [
        "修复从标的详情页返回后，自选列表行可能出现在 Pulse 标题和分组标签后方的问题；顶部栏现在独立占据布局空间，同时继续保留滚动位置。",
      ],
      en: [
        "Fixed watchlist rows appearing behind the Pulse header and list tabs after returning from a symbol page. The header now occupies its own layout space while the watchlist still preserves your scroll position.",
      ],
      ja: [
        "銘柄詳細から戻った後、ウォッチリストの行が Pulse ヘッダーやリストタブの背後に表示されることがある問題を修正しました。ヘッダーは独立したレイアウト領域を占め、スクロール位置の保持はそのままです。",
      ],
      ko: [
        "종목 페이지에서 돌아왔을 때 관심목록 행이 Pulse 헤더와 목록 탭 뒤로 들어가던 문제를 고쳤습니다. 헤더가 자기 레이아웃 공간을 차지하면서도 스크롤 위치는 그대로 유지됩니다.",
      ],
    },
  },
  {
    version: "0.11.2",
    date: "2026-08-11",
    kind: "fix",
    highlights: {
      zh: [
        "修复自选列表拖拽排序不稳定的问题：此前行情刷新会在拖拽途中打断放置指示线,悬停到目标位置后松手常常失败;现在排序期间行情写入自动暂停,退出排序后立即补齐。",
        "从标的详情页返回时,自选列表不再丢失滚动位置:列表页在子页面推入时保持存活,返回即回到原处。",
        "记录买入/卖出支持全键盘操作:在价格或数量输入框中直接按回车即可确认交易,「快速校准」编辑器同样支持回车保存。",
      ],
      en: [
        "Drag-to-reorder in the watchlist is now reliable. Quote refreshes used to reset the drop indicator mid-drag, so hovering over a target position made the drop fail; quote writes now hold while reorder mode is active and catch up the moment it ends.",
        "Returning from a symbol's detail page no longer loses your scroll position in the watchlist — the list stays alive underneath pushed pages instead of being rebuilt on the way back.",
        "Recording a buy or sell is now fully keyboard-driven: press Return in the price or quantity field to confirm the trade, and the quick-set position editor saves on Return the same way.",
      ],
      ja: [
        "ウォッチリストのドラッグ並べ替えを安定化しました。これまでは相場の更新がドラッグ中のドロップ位置インジケーターをリセットし、目標位置で止まってから離すと失敗することがありました。並べ替え中は相場の書き込みを一時停止し、終了した瞬間に追いつきます。",
        "銘柄詳細ページから戻ってもウォッチリストのスクロール位置が失われなくなりました。リストはページ遷移中も裏で保持され、戻るとそのままの位置に復帰します。",
        "売買の記録がキーボードだけで完結するようになりました。価格または数量の入力欄で Return を押すとそのまま確定し、クイック調整エディタも同様に Return で保存できます。",
      ],
      ko: [
        "관심목록의 끌어서 순서 바꾸기가 안정적으로 동작합니다. 예전에는 시세가 갱신되면서 놓을 위치 표시가 초기화돼, 목표 위치 위에 올려도 놓기가 실패했습니다. 이제 순서 바꾸기 중에는 시세 쓰기를 멈췄다가 끝나는 즉시 따라잡습니다.",
        "종목 상세에서 돌아와도 관심목록의 스크롤 위치를 잃지 않습니다. 목록이 다시 만들어지지 않고 열린 페이지 아래에 그대로 살아 있습니다.",
        "매수·매도 기록을 키보드만으로 끝낼 수 있습니다. 가격이나 수량 칸에서 Return을 누르면 거래가 확정되고, 보유 직접 입력도 같은 방식으로 저장됩니다.",
      ],
    },
  },
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
      ko: [
        "Pulse의 시각 아이덴티티를 처음의 시세 파형을 중심으로 새로 다듬었습니다. 짙은 남색 바탕에 또렷한 흰색 궤적, 실시간으로 갱신되는 가격에는 파란 꼬리를 씁니다.",
        "앱 아이콘, 메뉴 막대, 팝오버 헤더, 차트 로딩 화면, 내보낸 시세 이미지가 모두 같은 파형 언어를 씁니다.",
        "관심목록 행이 헤더 및 수신 상태와 같은 정렬선을 공유하면서도, 이름과 차트와 가격 사이 여백은 넉넉하게 유지합니다.",
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
      ko: [
        "일본어가 정식 앱 언어가 되었습니다. 설정 → 일반 → 언어에서 고르거나 Mac 설정을 따릅니다. 모든 화면과 메뉴, 오류, 공유 문구가 일본 증권 앱이 쓰는 용어(騰落率, 評価損益, 前日終値, 日足/週足/月足)를 씁니다.",
        "관심목록을 열려 있는 시장 순으로 정렬할 수 있습니다. 베이징 시간 8:00–17:00에는 홍콩 → 중국 A주 → 미국, 17:00–8:00에는 미국 → 홍콩 → 중국 A주 순입니다. 종목은 시장별로 묶이고 고정한 종목은 각 시장 안에서 자리를 지키며 암호화폐는 마지막입니다. 설정 → 시세 → 장 시간순으로 정렬에서 끌 수 있습니다.",
        "영문 문구를 다듬었습니다. 소문자 조각처럼 보이던 배지를 제목 형식으로 바꾸고, 몇몇 문구를 앱의 나머지와 같은 어조로 맞췄습니다.",
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
      ko: [
        "종목 페이지에서 그 티커 뒤의 사업을 설명합니다. 시세 옆 About 링크를 누르면 섹터와 산업을 포함한 기업 개요가 영문으로 열리며, 열었을 때만 받아 와 하루 동안 보관합니다.",
        "당일 손익을 각 주식이 실제로 오늘 치른 값 기준으로 계산합니다. 장중에 산 주식은 전일 종가가 아니라 체결가를 기준으로 삼고, 오늘 판 주식은 매도로 확정된 결과를 유지하며, 당일 수익률은 실제로 투입된 자금에 대해 계산합니다.",
        "전량 매도했다고 해서 한 번도 보유한 적 없는 것처럼 보이지 않습니다. 종목 페이지와 보유 화면이 첫 거래를 권하는 안내로 돌아가지 않고 실현 손익과 거래 기록을 그대로 보여 줍니다.",
        "차트 주기를 바꿀 때 새 봉이 오기 전에 '데이터 없음'이 잠깐 스치던 현상을 없앴습니다. 한 번 불러온 주기는 캐시에서 즉시 다시 그리고, 기다리는 동안에는 Pulse의 파형이 자리를 채웁니다.",
        "거래 삭제를 행의 컨텍스트 메뉴로 옮겼습니다. 포인터가 지나갈 때 금액을 밀어내던 호버 버튼을 대신합니다.",
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
      ko: [
        "Longbridge의 빈 세션 0값을 실제 장전·장후·야간 가격으로 잘못 읽던 문제를 고쳤습니다. 이제 여러 세션에서 가장 최근의 유효한 체결을 골라, 거짓 0원과 -100% 등락을 막습니다.",
        "시간외 거래 중에도 시세 통계는 마지막으로 끝난 정규장의 시가·고가·저가·거래량·거래대금을 계속 보여 줍니다. 시간외 수신값이 덮어쓰지 않습니다.",
        "관심목록 컨텍스트 메뉴에 현재 목록에서 제거가 생겼습니다. 목록 소속은 즉시 반영되고, 종목과 보유 내역은 그 종목이 속한 다른 목록에서 그대로 남습니다.",
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
      ko: [
        "텍스트로 복사가 관심목록이나 상세 화면을 영문 구조화 시세 스냅숏으로 내보냅니다. 종목 메타데이터, 시세, 출처, 시각, 세션 정보가 담기고, 상세에서 내보내면 LLM 분석에 바로 쓸 수 있는 차트 OHLCV까지 포함됩니다.",
        "관심목록 정렬에 목록별 고정과 네이티브 끌어서 순서 바꾸기가 생겼습니다. 고정 경계를 넘으면 자동으로 고정·해제되고, 고정을 풀면 이전의 사용자 지정 위치로 돌아가며, 새로 추가한 종목은 일반 구간 맨 앞에 옵니다.",
        "여러 시장에 걸친 검색에서 암호화폐의 정확한 기초자산·페어 일치는 앞에 두되, 관련 없는 암호화폐 결과보다는 증권을 먼저 보여 줍니다.",
        "Longbridge 실패 시 서버가 준 원래 오류를 보존해 표시하고, 네트워크 오류와 인증 오류를 더 정확히 구분하며, 검증 전에 기존 권한을 버리지 않고 그 자리에서 안전하게 다시 인증할 수 있습니다.",
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
      ko: [
        "보유 거래: 매수와 매도를 거래 원장으로 재생해 수량과 이동평균 단가, 실현 손익을 계산합니다. 보유 화면과 월별 거래 기록, 보유 직접 입력을 함께 제공합니다.",
        "공매도: 먼저 팔아 숏을 열고 되사서 청산하며 손익을 확정합니다. 0을 지나는 거래는 체결가에서 방향이 바뀌고, 숏 수량은 음수로 표시됩니다.",
        "정규장 밖에서는 상세 화면이 실시간 장전·장후·야간 가격 옆에 마지막 정규장 종가와 그날의 등락을 함께 보여 줍니다.",
        "지수는 장전·장후 구간과 세션 음영, 세션 표시를 그리지 않습니다. 정규장에만 산출되기 때문입니다.",
        "관심목록의 추세선은 항상 정규장을 담고, 시간외 설정은 상세 차트에만 적용됩니다.",
        "컨텍스트 메뉴에 네이티브 다중 선택 목록 소속과 순서 바꾸기 항목이 생겼고, 보유 요약에서 해당 페이지로 바로 이동합니다.",
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
      ko: [
        "관심목록과 공유 카드의 추세선도 시간외 설정을 따릅니다. 장전·장후는 회색 구간으로 그려지고 9:30 / 16:00 경계에 가는 구분선이 들어가, 상세 차트와 모양이 같아집니다.",
        "장전 추세선이 차트 꼬리로 뭉치던 문제를 고쳤습니다. 시간외 데이터가 최신 페이지를 밀어낼 때 Longbridge 분봉 기록이 직전 정규장을 채워 넣습니다.",
        "K선 차트를 공유하면 보이는 확대 구간 그대로의 진짜 캔들 카드가 만들어집니다. 거래량과 세션 음영, 거래소 시각 기준 구간까지 담깁니다.",
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
      ko: [
        "K선 차트가 진짜 캔들이 되었습니다. 거래량이 정확히 맞춰지고, 마우스 휠과 트랙패드 확대, 가로 스크롤을 지원합니다.",
        "거래량을 포함한 5분·15분·30분·60분 K선을 추가했습니다. 작은 분할 컨트롤에서 고릅니다.",
        "미국주식 분시 차트가 기본적으로 미 동부시간 04:00–20:00의 장전·장후 거래를 보여 줍니다. 설정에서 끌 수 있습니다.",
        "Longbridge 분봉 기록이 필요할 때 뒤 페이지까지 받아 이전 장전 데이터를 되살리고, 실패하면 최신 페이지를 그대로 지킵니다.",
        "주봉 호버 카드가 그 거래 주간의 전체 범위를 보여 줍니다. 차트 라벨과 호버 성능, 검색 포커스도 함께 다듬었습니다.",
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
      ko: [
        "공유 카드를 새로 만들었습니다. 관심목록 카드는 고른 목록 이름을 제목으로 단 1:1 캔버스이며, 모든 종목을 담고 목록이 길면 함께 늘어납니다.",
        "종목 공유 카드는 여백 없는 추세 차트와 당일 변동폭 막대를 갖춘 16:9 포스터 형태가 되었습니다.",
        "공유 카드가 시스템 외형과 상승·하락 색상 설정을 따르고, 면책 문구 대신 브랜드 푸터가 들어갑니다.",
        "검색이 툴바로 옮겨 갔습니다. 돋보기나 ⌘F를 누르면 최근 검색(지우기 가능)과 인기 종목이 있는 전용 패널이 열립니다.",
        "검색 결과에서 관심목록에 없는 종목도 전체 시세 페이지로 열 수 있고, 거기서 바로 추가할 수 있습니다.",
        "중국 A주와 홍콩 분시 차트가 점심 휴장을 건너뛰고 이어서 그려집니다.",
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
      ko: [
        "Longbridge 시세가 공식 SDK가 협상한 패키지와 시각을 근거로 실시간과 지연을 구분합니다.",
        "지연된 Longbridge 데이터는 더 신선한 대체 소스가 있으면 자리를 내주고, 상세 화면은 항상 실제 출처와 지연을 보여 줍니다.",
        "OAuth 신원이 Mac의 지역이나 시간대에 따라 바뀌지 않습니다. 기존 세션은 그대로 유효하며, 영향을 받은 경우 설정에서 인증을 갱신할 수 있습니다.",
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
      ko: [
        "관심목록을 컨텍스트 메뉴에서 바로 지울 수 있습니다. 메뉴 막대 패널을 닫아 버리는 확인 창이 뜨지 않습니다.",
        "그 목록에만 있던 종목은 다른 목록으로 안전하게 옮겨지고, 보유 정보는 그대로 남습니다.",
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
      ko: [
        "자동 업데이트의 버전 비교를 고쳐 Pulse 0.5.1에서도 0.6 계열을 찾아 설치할 수 있습니다.",
        "0.6.0에서 들어간 Longbridge SDK, 정리된 지수 체계, 안정적인 종목명, 유지되는 설정이 함께 포함됩니다.",
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
      ko: [
        "Longbridge 시세를 버전 고정된 공식 SDK로 옮기고, 복구와 종목별 대체 경로를 강화했습니다.",
        "지수의 식별자와 이름, 검색 라벨, 종목 매핑을 여러 소스에 걸쳐 하나로 정리했습니다.",
        "지수는 직접 거래할 수 없는 기준 지표로 다루며, 보유 편집을 더 이상 제공하지 않습니다.",
        "종목명이 시세 제공처 우선순위를 따릅니다. 대체 소스가 이름을 낮추지 못하고, 더 높은 우선순위의 소스만 개선할 수 있습니다.",
        "상승·하락 색상이나 관심목록 지표 같은 표시 설정이 앱을 다시 켜도 유지됩니다.",
        "긴 관심목록이 매끄럽게 스크롤되고, 잘린 이름은 네이티브 툴팁으로 전체를 보여 줍니다.",
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
      ko: [
        "쓸 만한 소스가 하나라도 응답하면 검색 결과를 바로 보여 줍니다. 모든 제공처를 기다리지 않습니다.",
        "검색에 마감 시간이 생겼고, 새 검색에 밀린 요청은 깔끔하게 취소되며, 일시적인 빈 결과는 더 이상 캐시하지 않습니다.",
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
      ko: [
        "이름 붙인 관심목록을 여러 개 만들 수 있습니다. 생성·이름 변경·삭제·끌어서 순서 바꾸기와 ⌘1–⌘9 단축키를 지원합니다.",
        "검색이 여러 제공처를 동시에 돌리고 결과를 고른 목록에 추가합니다. 한 종목이 여러 목록에 속할 수 있습니다.",
        "메뉴 막대 시세 순환을 특정 관심목록으로 지정할 수 있습니다.",
        "Longbridge 재연결과 인증 이전이 더 안정적이며, 상태 표시와 재시도 조작이 명확해졌습니다.",
        "공유 이미지에 pulseticker.app 서명이 조용히 들어가고, 시장별 거래대금 값을 바로잡았습니다.",
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
      ko: [
        "앱 안에서 Pulse 웹사이트와 GitHub로 바로 가는 링크를 추가했습니다.",
        "설정·검색·Longbridge 연결의 전환을 부드럽게 다듬되, 동작 줄이기 설정을 존중합니다.",
        "웹사이트에 고정된 최신 다운로드 주소가 생겼고, Pulse가 쓰는 시세 데이터 제공처를 밝힙니다.",
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
      ko: [
        "암호화폐 검색·시세·차트를 Binance 스팟 공개 API로 옮기고, 패널이 열려 있는 동안 1초 간격 WebSocket으로 갱신합니다.",
        "암호화폐 종목을 BTC/USDT 같은 기초자산·결제자산 페어로 표준화하고 자동으로 이전했습니다.",
        "Binance와 Longbridge 스트림을 암호화폐와 증권에 대해 동시에 돌릴 수 있습니다.",
        "데이터 소스 설정 전반에서 상태와 시장 지원 범위 설명을 통일했습니다.",
        "익명 제품 분석을 선택적으로 추가했습니다. 종목, 관심목록, 보유, 검색어, 인증 정보는 절대 포함하지 않습니다.",
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
      ko: [
        "상세 화면에서 종목을 공유할 수 있습니다. 개인 보유 정보는 빠집니다.",
        "관심목록과 상세, 공유 이미지가 같은 당일 1분 추세 데이터를 씁니다.",
        "추세 데이터를 목록과 상세 캐시가 공유해, 어느 화면에서 보든 같은 시세 스냅숏을 봅니다.",
        "패널을 열고 닫는 동안에도 실시간 수신 상태가 흔들리지 않습니다.",
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
      ko: [
        "브라우저 인증이나 OpenAPI 키로 Longbridge 실시간 시세를 붙였습니다. 인증 정보는 이 기기의 키체인에만 둡니다.",
        "끊기지 않는 실시간 수신을 추가했고, 미국주식 야간 세션의 상태와 가격을 따로 다룹니다.",
        "텐센트·Yahoo·Longbridge가 각자의 갱신 주기를 갖고, 장 시간에 맞춰 조회합니다.",
        "데이터 소스 상세 화면을 다시 만들어 연결, 지원 범위, 갱신 방식, 신선도를 설명합니다.",
        "관심목록 하단이 '실시간 수신 중' 같은 수신 상태를 알려 줍니다.",
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
      ko: [
        "상세 통계에서 거래대금을 변동폭으로 바꿔, 그날의 고가–저가 폭을 더 분명히 보여 줍니다.",
        "가격 변화에 방향이 있는 롤링 숫자를 넣고, 페이지·버튼·주기 전환을 부드럽게 다듬었습니다.",
        "모든 움직임이 macOS의 동작 줄이기 설정을 따릅니다.",
        "상세 제목이 잘리던 문제를 고치고, 번역이 긴 언어에서도 주기 선택기가 잘 맞도록 개선했습니다.",
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
      ko: [
        "브랜드가 들어간 모바일 친화 관심목록 이미지를 클립보드로 바로 복사할 수 있습니다.",
        "공유 이미지가 고른 지표를 따르고 관심목록 길이에 맞춰 늘어납니다.",
        "중국 A주 분시 데이터는 실시간 텐센트를 우선 쓰고, Yahoo를 대체 경로와 과거 봉 데이터로 씁니다.",
        "복사 완료 안내가 시장 상태를 가리지 않고 나타납니다.",
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
      ko: [
        "영어와 중국어 간체를 추가하고, 시스템 언어 감지와 수동 전환을 지원합니다.",
        "Yahoo Finance를 통해 암호화폐 검색·시세·분시 차트를 추가했습니다.",
        "검색·시세·봉 데이터에 캐시와 요청 간격 조절을 넣었습니다.",
        "검색 포커스와 로딩 표시를 개선하고, 신선도·출처·시장 시각 정보를 나눠서 보여 줍니다.",
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
      ko: ["정식 Pulse macOS 앱 아이콘을 넣었습니다."],
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
      ko: [
        "첫 설치에 적합한 DMG 설치 파일을 추가했습니다.",
        "샌드박스 빌드에서 Sparkle 자동 업데이트가 되도록 고쳤습니다.",
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
      ko: [
        "첫 공개 미리보기를 다듬어, 메뉴 막대 관심목록 스크린숏을 더 또렷하게 하고 설치 안내를 정리했습니다.",
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
      ko: [
        "Pulse가 미국·홍콩·중국 주식과 지수, ETF를 위한 macOS 메뉴 막대 시세 앱으로 정식 공개되었습니다.",
        "관심목록, 메뉴 막대 시세 순환, 보유와 손익, 상세 통계, 분시 차트, 캔들차트를 담았습니다.",
        "텐센트와 Yahoo Finance 제공처 라우팅과 자동 대체 경로를 넣었습니다.",
        "장 시간에 맞춘 갱신과 관심목록·보유·설정의 로컬 저장을 넣었습니다.",
      ],
    },
  },
];
