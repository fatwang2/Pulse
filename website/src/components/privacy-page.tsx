import { Link } from "@tanstack/react-router";
import { SiteHeader } from "./site-header";
import {
  aboutPath,
  contactPath,
  homePath,
  type Language,
} from "../i18n";

const translations = {
  zh: {
    title: "隐私政策",
    lastUpdated: "最后更新：2026 年 8 月",
    intro:
      "Pulse 尊重你的隐私。本政策说明 Pulse 收集什么、不收集什么，以及你的数据存在哪里。",
    analyticsHeading: "匿名使用分析",
    analytics: [
      "Pulse 使用 TelemetryDeck 收集匿名的基础产品使用数据。匿名分析默认开启，你可以在「设置 → 通用 → 分享匿名使用数据」中随时关闭。关闭后，Pulse 不再发送新的分析事件。",
      "目前只发送以下产品交互事件：应用启动、浮层打开、设置打开、手动刷新、以及重新开启分析时的事件。TelemetryDeck 的 Swift SDK 会自动附加基本技术上下文，如 Pulse 版本与构建号、macOS 版本、设备型号与架构、语言、地区、时区、显示属性，以及构建是否为 Debug 或 App Store 版本。在 macOS 上，SDK 还会生成一个随机的伪匿名设备标识符和会话标识符。Pulse 不向 TelemetryDeck 提供姓名、邮箱、账户 ID 或其他自定义用户标识符。",
      "Pulse 绝不会将你关注的标的、自选列表、持仓、数量、成本、搜索文本、行情数据响应、Longbridge 凭证或其他用户提供的内容加入分析事件。TelemetryDeck 的隐私清单声明数据用于分析且不与用户身份关联，也不用于跟踪。Pulse 没有广告或跨应用跟踪。",
    ],
    localHeading: "本地存储与凭证",
    local: [
      "你的自选列表、持仓和设置存储在本地，不会上传到任何服务器。如果你选择连接 Longbridge OpenAPI 账户，凭证仅保存在本地 Keychain 中，不会离开你的 Mac。",
    ],
    openSourceHeading: "开源可审计",
    openSource: [
      "Pulse 是开源项目（MIT 协议）。分析事件的完整边界有意保持在 PulseTelemetry.swift 一个文件中，任何人都可以审计实现细节。完整源代码托管在 GitHub。",
    ],
    companyHeading: "运营方",
    company: [
      "Pulse 由 SuperAgents, LLC 运营，注册地址：131 Continental Dr, Suite 305, Newark, Delaware 19713, United States。如有隐私相关问题，请联系 hello@pulseticker.app。",
    ],
    linksHeading: "其他页面",
    links: {
      about: "关于 Pulse",
      contact: "联系我们",
      home: "返回首页",
    },
  },
  en: {
    title: "Privacy Policy",
    lastUpdated: "Last updated: August 2026",
    intro:
      "Pulse respects your privacy. This policy explains what Pulse collects, what it does not, and where your data lives.",
    analyticsHeading: "Anonymous usage analytics",
    analytics: [
      "Pulse uses TelemetryDeck to collect anonymous basic product-usage data. Anonymous analytics are enabled by default and can be disabled at any time in Settings → General → Share Anonymous Usage Data. Once disabled, Pulse stops queuing new analytics events.",
      "Pulse currently sends only these product-interaction events: app launched, popover opened, settings opened, manual refresh, and an event sent only when analytics is turned back on. TelemetryDeck's Swift SDK automatically adds basic technical context such as the Pulse version and build, macOS version, device model and architecture, language, locale, region, time zone, display properties, and whether the build is a debug or App Store build. On macOS, the SDK also generates a random pseudonymous device identifier and a session identifier. Pulse does not provide TelemetryDeck with a name, email address, account identifier, or other custom user identifier.",
      "Pulse never adds watched symbols, watchlists, positions, quantities, cost bases, search text, market-data responses, Longbridge credentials, or other user-provided content to analytics events. TelemetryDeck's bundled privacy manifest declares product-interaction data and a device identifier for analytics; the data is not linked to the user's identity and is not used for tracking. Pulse has no advertising or cross-app tracking.",
    ],
    localHeading: "Local storage and credentials",
    local: [
      "Your watchlists, positions, and settings are stored locally and are never uploaded to any server. If you choose to connect a Longbridge OpenAPI account, credentials are stored only in the local Keychain and never leave your Mac.",
    ],
    openSourceHeading: "Open source and auditable",
    openSource: [
      "Pulse is open source under the MIT license. The complete analytics event boundary is intentionally kept in a single file, PulseTelemetry.swift, so the implementation can be audited. The full source code is on GitHub.",
    ],
    companyHeading: "Operator",
    company: [
      "Pulse is operated by SuperAgents, LLC, registered at 131 Continental Dr, Suite 305, Newark, Delaware 19713, United States. For privacy-related questions, contact hello@pulseticker.app.",
    ],
    linksHeading: "Other pages",
    links: {
      about: "About Pulse",
      contact: "Contact",
      home: "Back to home",
    },
  },
  ja: {
    title: "プライバシーポリシー",
    lastUpdated: "最終更新：2026年8月",
    intro:
      "Pulse はプライバシーを尊重します。本ポリシーは、Pulse が何を収集し、何を収集せず、データがどこに保存されるかを説明します。",
    analyticsHeading: "匿名利用分析",
    analytics: [
      "Pulse は TelemetryDeck を使用して匿名の基本製品利用データを収集します。匿名分析はデフォルトで有効で、「設定 → 一般 → 匿名の利用データを共有」からいつでも無効にできます。無効にすると、Pulse は新しい分析イベントの送信を停止します。",
      "現在送信される製品インタラクションイベントは以下のみです：アプリ起動、ポップオーバー表示、設定表示、手動リフレッシュ、分析を再有効化した際のイベント。TelemetryDeck の Swift SDK は、Pulse のバージョンとビルド、macOS バージョン、デバイスモデルとアーキテクチャ、言語、地域、タイムゾーン、表示プロパティ、デバッグビルドか App Store ビルドかなどの基本技術コンテキストを自動的に付加します。macOS では、SDK はランダムな疑似匿名デバイス識別子とセッション識別子も生成します。Pulse は TelemetryDeck に氏名、メールアドレス、アカウント ID、その他のカスタムユーザー識別子を提供しません。",
      "Pulse はウォッチリスト、評価損益、数量、コストベース、検索テキスト、行情データレスポンス、Longbridge 認証情報、その他のユーザー提供コンテンツを分析イベントに含めません。TelemetryDeck のプライバシーマニフェストは、分析用の製品インタラクションデータとデバイス識別子を宣言しており、ユーザーの身份にはリンクされず、トラッキングにも使用されません。Pulse には広告やクロスアプリトラッキングはありません。",
    ],
    localHeading: "ローカルストレージと認証情報",
    local: [
      "ウォッチリスト、評価損益、設定はローカルに保存され、サーバーにアップロードされることはありません。Longbridge OpenAPI アカウントを接続した場合、認証情報はローカルの Keychain にのみ保存され、Mac から外に出ることはありません。",
    ],
    openSourceHeading: "オープンソースと監査可能性",
    openSource: [
      "Pulse は MIT ライセンスのオープンソースプロジェクトです。分析イベントの完全な境界は意図的に単一ファイル PulseTelemetry.swift に保たれており、実装を監査できます。全ソースコードは GitHub にあります。",
    ],
    companyHeading: "運営元",
    company: [
      "Pulse は SuperAgents, LLC が運営しています。登録住所：131 Continental Dr, Suite 305, Newark, Delaware 19713, United States。プライバシーに関するご質問は hello@pulseticker.app まで。",
    ],
    linksHeading: "その他のページ",
    links: {
      about: "Pulse について",
      contact: "お問い合わせ",
      home: "ホームに戻る",
    },
  },
  ko: {
    title: "개인정보 처리방침",
    lastUpdated: "최종 업데이트: 2026년 8월",
    intro:
      "Pulse는 개인정보를 존중합니다. 이 방침은 Pulse가 무엇을 수집하고, 무엇을 수집하지 않으며, 데이터가 어디에 저장되는지 설명합니다.",
    analyticsHeading: "익명 사용 분석",
    analytics: [
      "Pulse는 TelemetryDeck을 사용하여 익명의 기본 제품 사용 데이터를 수집합니다. 익명 분석은 기본적으로 활성화되어 있으며, 설정 → 일반 → 익명 사용 데이터 공유에서 언제든 비활성화할 수 있습니다. 비활성화하면 Pulse는 새 분석 이벤트 전송을 중지합니다.",
      "현재 전송되는 제품 상호작용 이벤트는 다음뿐입니다: 앱 실행, 팝오버 표시, 설정 표시, 수동 새로고침, 분석을 다시 켤 때의 이벤트. TelemetryDeck의 Swift SDK는 Pulse 버전과 빌드, macOS 버전, 기기 모델과 아키텍처, 언어, 지역, 시간대, 디스플레이 속성, 디버그 빌드 여부 등의 기본 기술 컨텍스트를 자동으로 추가합니다. macOS에서 SDK는 무작위 가명 식별자와 세션 식별자도 생성합니다. Pulse는 TelemetryDeck에 이름, 이메일, 계정 ID 또는 기타 사용자 식별자를 제공하지 않습니다.",
      "Pulse는 관심 종목, 관심목록, 보유 손익, 수량, 매입가, 검색어, 시세 데이터 응답, Longbridge 인증 정보 또는 기타 사용자 제공 콘텐츠를 분석 이벤트에 추가하지 않습니다. TelemetryDeck의 개인정보 매니페스트는 분석용 제품 상호작용 데이터와 기기 식별자를 선언하며, 사용자 신원에 연결되지 않고 추적에도 사용되지 않습니다. Pulse에는 광고나 크로스 앱 추적이 없습니다.",
    ],
    localHeading: "로컬 저장소와 인증 정보",
    local: [
      "관심목록, 보유 손익, 설정은 로컬에 저장되며 어떤 서버에도 업로드되지 않습니다. Longbridge OpenAPI 계정을 연결하면 인증 정보는 로컬 Keychain에만 저장되고 Mac 밖으로 나가지 않습니다.",
    ],
    openSourceHeading: "오픈소스와 감사 가능성",
    openSource: [
      "Pulse는 MIT 라이선스 오픈소스 프로젝트입니다. 분석 이벤트의 전체 경계는 의도적으로 단일 파일 PulseTelemetry.swift에 유지되어 구현을 감사할 수 있습니다. 전체 소스 코드는 GitHub에 있습니다.",
    ],
    companyHeading: "운영사",
    company: [
      "Pulse는 SuperAgents, LLC가 운영합니다. 등록 주소: 131 Continental Dr, Suite 305, Newark, Delaware 19713, United States. 개인정보 관련 문의는 hello@pulseticker.app로 연락해 주세요.",
    ],
    linksHeading: "다른 페이지",
    links: {
      about: "Pulse 소개",
      contact: "연락처",
      home: "홈으로",
    },
  },
} as const;

export function PrivacyPage({ language }: { language: Language }) {
  const copy = translations[language];

  return (
    <main className="info-page">
      <SiteHeader language={language} page="privacy" />

      <section className="info-hero shell">
        <h1>{copy.title}</h1>
        <p className="info-last-updated">{copy.lastUpdated}</p>
        <p>{copy.intro}</p>
      </section>

      <section className="info-content shell">
        <div className="info-section">
          <h2>{copy.analyticsHeading}</h2>
          {copy.analytics.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>

        <div className="info-section">
          <h2>{copy.localHeading}</h2>
          {copy.local.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>

        <div className="info-section">
          <h2>{copy.openSourceHeading}</h2>
          {copy.openSource.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>

        <div className="info-section">
          <h2>{copy.companyHeading}</h2>
          {copy.company.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>

        <nav className="info-links" aria-label={copy.linksHeading}>
          <Link to={homePath(language)}>{copy.links.home}</Link>
          <Link to={aboutPath(language)}>{copy.links.about}</Link>
          <Link to={contactPath(language)}>{copy.links.contact}</Link>
        </nav>
      </section>
    </main>
  );
}
