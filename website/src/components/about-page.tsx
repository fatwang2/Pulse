import { Link } from "@tanstack/react-router";
import { SiteHeader } from "./site-header";
import {
  changelogPath,
  contactPath,
  homePath,
  organizationInfo,
  privacyPath,
  type Language,
} from "../i18n";

const translations = {
  zh: {
    title: "Pulse 只解决一个问题：\n用最短时间看到你关心的市场。",
    intro:
      "它不是交易终端，没有下单、没有执行、没有券商连接。它是一台行情查看器——把你关心的价格、走势和持仓盈亏放进菜单栏，从盘前到盘后，不打断手头的事。",
    storyHeading: "为什么做 Pulse",
    story: [
      "市面上的行情工具要么是重量级的交易终端，打开就要等几秒、切好几个标签页才能看到自选；要么是浏览器里一个标签页，需要你主动去翻。Pulse 的出发点很简单：看行情应该是一眼的事，不该比看时间更费力。",
      "所以 Pulse 长在菜单栏。点一下图标，浮层展开，自选、走势、持仓盈亏一览无余；点回去，浮层收起，你继续做你正在做的事。它不试图替代你的交易平台，只替你省掉那些为了看一眼价格而打断工作的时刻。",
    ],
    makerHeading: "谁在维护 Pulse",
    maker: [
      "Pulse 由 SuperAgents, LLC 开发和维护。这是一家在美国特拉华州注册的有限责任公司。Pulse 是开源项目（MIT 协议），源代码托管在 GitHub，任何人都可以审计、贡献或自行构建。",
      "团队目前专注于 macOS 和 Omarchy Quattro 两个平台。未来可能会扩展到其他端，但核心定位不变：快速看行情，而不是成为又一个全能交易平台。",
    ],
    dataHeading: "数据来源",
    data: [
      "Pulse 聚合多个公开行情数据源：Binance（加密货币）、Yahoo Finance、腾讯、新浪、Naver（韩国）、东方财富和上海黄金交易所。可选连接你自己的 Longbridge OpenAPI 账户，获取港股、美股和 A 股的官方实时推送行情。",
      "所有行情数据仅供参考，不构成投资建议。各数据源的覆盖范围和延迟因市场而异，具体可在每个标的的详情页查看。",
    ],
    linksHeading: "了解更多",
    links: {
      changelog: "更新日志",
      contact: "联系我们",
      privacy: "隐私政策",
      home: "返回首页",
      github: "在 GitHub 查看源码",
    },
  },
  en: {
    title: "Pulse solves one problem:\nseeing your markets in the shortest possible time.",
    intro:
      "It is not a trading terminal. There is no order placement, no execution, no broker connection for trading. It is a market watcher — it puts the prices, trends, and position P&L you care about in the menu bar, from pre-market to after hours, without interrupting what you are doing.",
    storyHeading: "Why we built Pulse",
    story: [
      "Most market tools are either heavyweight trading terminals that take seconds to launch and several tab switches to reach your watchlist, or a browser tab you have to remember to check. Pulse starts from a simpler idea: checking the market should be a glance, not an errand.",
      "So Pulse lives in the menu bar. Click the icon and a popover opens with your watchlists, trends, and position P&L in one view. Click away and it collapses — you go back to what you were doing. It does not try to replace your trading platform. It just saves you the moments you would otherwise spend interrupting your work to check a price.",
    ],
    makerHeading: "Who maintains Pulse",
    maker: [
      "Pulse is developed and maintained by SuperAgents, LLC, a limited liability company registered in Delaware, USA. Pulse is open source under the MIT license — the full source code is on GitHub, and anyone can audit it, contribute, or build it themselves.",
      "The team currently focuses on macOS and Omarchy Quattro. More platforms may follow, but the core mission stays the same: fast market glances, not another all-in-one trading platform.",
    ],
    dataHeading: "Data sources",
    data: [
      "Pulse aggregates several public market-data sources: Binance (crypto), Yahoo Finance, Tencent, Sina, Naver (Korea), Eastmoney, and the Shanghai Gold Exchange. You can optionally connect your own Longbridge OpenAPI account for official real-time push quotes on Hong Kong, US, and China A-share markets.",
      "All market data is for reference only and is not investment advice. Coverage and delay vary by source and market — each symbol's detail page shows the active source and its freshness.",
    ],
    linksHeading: "Learn more",
    links: {
      changelog: "Changelog",
      contact: "Contact",
      privacy: "Privacy",
      home: "Back to home",
      github: "View source on GitHub",
    },
  },
  ja: {
    title: "Pulse が解決するのは一つの問題：\n最短時間で市場を把握すること。",
    intro:
      "Pulse は取引ターミナルではありません。発注も執行も取引向けのブローカー接続もありません。これはマーケットウォッチャーです——気になる価格、トレンド、評価損益をメニューバーに置き、プレマーケットからアフターマークまで、作業を中断せずに確認できます。",
    storyHeading: "Pulse を作った理由",
    story: [
      "既存の行情ツールは、重い取引ターミナルかブラウザのタブのどちらかです。ターミナルは起動に数秒かかり、ウォッチリストにたどり着くまで複数のタブを切り替える必要があります。Pulse の出発点はもっとシンプルです：相場を確認するのは一目の作業であるべきで、わざわざ足を運ぶことではない。",
      "だから Pulse はメニューバーにあります。アイコンをクリックすればポップオーバーが開き、ウォッチリスト、トレンド、評価損益が一目で分かります。クリックすれば閉じ、元の作業に戻ります。取引プラットフォームを置き換えるつもりはありません。ただ、価格を確認するために仕事を中断する瞬間を省くためです。",
    ],
    makerHeading: "Pulse のメンテナ",
    maker: [
      "Pulse は SuperAgents, LLC（米国デラウェア州登録の合同会社）が開発・保守しています。Pulse は MIT ライセンスのオープンソースプロジェクトで、全ソースコードは GitHub にあります。誰でも監査、貢献、自行ビルドが可能です。",
      "現在は macOS と Omarchy Quattro に注力しています。今後さらにプラットフォームを増やす可能性もありますが、核心のミッションは変わりません：素早い行情確認であり、もう一つの全能取引プラットフォームになることではありません。",
    ],
    dataHeading: "データ提供元",
    data: [
      "Pulse は複数の公開行情データソースを統合しています：Binance（暗号資産）、Yahoo Finance、Tencent、Sina、Naver（韓国）、Eastmoney、上海金取引所。オプションで Longbridge OpenAPI アカウントを接続し、香港・米国・中国 A 株の公式リアルタイムプッシュ行情を取得することもできます。",
      "行情データはあくまで参考用であり、投資助言ではありません。カバレッジと遅延はソースと市場により異なり、各銘柄の詳細ページでアクティブなソースと鮮度を確認できます。",
    ],
    linksHeading: "さらに詳しく",
    links: {
      changelog: "更新履歴",
      contact: "お問い合わせ",
      privacy: "プライバシー",
      home: "ホームに戻る",
      github: "GitHub でソースを見る",
    },
  },
  ko: {
    title: "Pulse가 푸는 문제는 하나:\n가장 짧은 시간에 시장을 확인하는 것.",
    intro:
      "Pulse는 거래 터미널이 아닙니다. 주문 집행도, 거래용 브로커 연결도 없습니다. 시세 뷰어입니다——신경 쓰는 가격, 흐름, 보유 손익을 메뉴 막대에 올려, 장전부터 장후까지 하던 일을 멈추지 않고 확인합니다.",
    storyHeading: "Pulse를 만든 이유",
    story: [
      "기존 시세 도구는 무거운 거래 터미널이거나 브라우저 탭입니다. 터미널은 켜는 데 몇 초가 걸리고 관심목록까지 여러 탭을 거쳐야 합니다. Pulse의 출발점은 더 단순합니다: 시장을 확인하는 건 눈길이어야지, 심부름이어서는 안 됩니다.",
      "그래서 Pulse는 메뉴 막대에 있습니다. 아이콘을 누르면 패널이 열려 관심목록, 흐름, 보유 손익이 한눈에 들어옵니다. 다시 누르면 닫히고 원래 하던 일로 돌아갑니다. 거래 플랫폼을 대체하려는 게 아닙니다. 가격을 보려고 일을 끊는 순간을 아껴 줄 뿐입니다.",
    ],
    makerHeading: "Pulse를 관리하는 곳",
    maker: [
      "Pulse는 SuperAgents, LLC(미국 델라웨어주 등록 유한책임회사)가 개발하고 유지합니다. Pulse는 MIT 라이선스 오픈소스 프로젝트로, 전체 소스 코드는 GitHub에 있습니다. 누구나 감사, 기여, 직접 빌드가 가능합니다.",
      "현재는 macOS와 Omarchy Quattro에 집중하고 있습니다. 앞으로 더 많은 플랫폼이 추가될 수 있지만, 핵심 미션은 변하지 않습니다: 빠른 시세 확인이지, 또 하나의 만능 거래 플랫폼이 되는 것이 아닙니다.",
    ],
    dataHeading: "데이터 제공처",
    data: [
      "Pulse는 여러 공개 시세 데이터 소스를 통합합니다: Binance(암호화폐), Yahoo Finance, Tencent, Sina, Naver(한국), Eastmoney, 상하이 금 거래소. 선택적으로 Longbridge OpenAPI 계정을 연결해 홍콩·미국·중국 A주의 공식 실시간 푸시 시세를 받을 수도 있습니다.",
      "모든 시세 데이터는 참고용이며 투자 자문이 아닙니다. 범위와 지연은 소스와 시장마다 다르며, 각 종목 상세 페이지에서 활성 소스와 갱신 주기를 확인할 수 있습니다.",
    ],
    linksHeading: "더 알아보기",
    links: {
      changelog: "업데이트 내역",
      contact: "연락처",
      privacy: "개인정보",
      home: "홈으로",
      github: "GitHub에서 소스 보기",
    },
  },
} as const;

const repositoryUrl = "https://github.com/fatwang2/Pulse";

export function AboutPage({ language }: { language: Language }) {
  const copy = translations[language];

  return (
    <main className="info-page">
      <SiteHeader language={language} page="about" />

      <section className="info-hero shell">
        <h1>
          {copy.title.split("\n").map((line, index) => (
            <span key={line}>
              {line}
              {index === 0 ? <br /> : null}
            </span>
          ))}
        </h1>
        <p>{copy.intro}</p>
      </section>

      <section className="info-content shell">
        <div className="info-section">
          <h2>{copy.storyHeading}</h2>
          {copy.story.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>

        <div className="info-section">
          <h2>{copy.makerHeading}</h2>
          {copy.maker.map((paragraph, index) => (
            <p key={index}>
              {paragraph}
              {index === 0 && language === "en" ? (
                <>
                  {" "}
                  <strong>{organizationInfo.legalName}</strong>, {organizationInfo.address.streetAddress}, {organizationInfo.address.addressLocality}, {organizationInfo.address.addressRegion} {organizationInfo.address.postalCode}, {organizationInfo.address.addressCountry}.
                </>
              ) : null}
            </p>
          ))}
        </div>

        <div className="info-section">
          <h2>{copy.dataHeading}</h2>
          {copy.data.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>

        <nav className="info-links" aria-label={copy.linksHeading}>
          <Link to={homePath(language)}>{copy.links.home}</Link>
          <Link to={changelogPath(language)}>{copy.links.changelog}</Link>
          <Link to={contactPath(language)}>{copy.links.contact}</Link>
          <Link to={privacyPath(language)}>{copy.links.privacy}</Link>
          <a href={repositoryUrl} target="_blank" rel="noreferrer">
            {copy.links.github}
          </a>
        </nav>
      </section>
    </main>
  );
}
