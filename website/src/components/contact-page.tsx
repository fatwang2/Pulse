import { Link } from "@tanstack/react-router";
import { SiteHeader } from "./site-header";
import {
  aboutPath,
  homePath,
  organizationInfo,
  privacyPath,
  type Language,
} from "../i18n";

const repositoryIssuesUrl = "https://github.com/fatwang2/Pulse/issues";

const translations = {
  zh: {
    title: "联系我们",
    intro:
      "有问题、建议或发现 bug？我们很乐意听到你的声音。以下是最合适的联系方式。",
    generalHeading: "一般咨询与产品反馈",
    general: [
      "产品问题、功能建议或一般咨询，请发邮件到 hello@pulseticker.app。我们会尽快回复。",
      "如果是 bug 报告，请在 GitHub Issues 中提交，并附上 macOS 版本、Pulse 版本以及复现步骤。截图或录屏会很有帮助。",
    ],
    technicalHeading: "技术问题与安全",
    technical: [
      "涉及数据源、API 或安全相关的问题，请发邮件到 sys@pulseticker.app。如果你发现安全漏洞，请勿在公开的 GitHub Issue 中提交，直接邮件联系。",
    ],
    responseHeading: "回复时间",
    response: [
      "这是一个由小团队维护的开源项目。我们通常会在 1–3 个工作日内回复邮件和 GitHub Issue，但不保证固定响应时间。如果你的 Issue 没有得到及时回复，请耐心等待或再发一次跟进。",
    ],
    linksHeading: "其他页面",
    links: {
      about: "关于 Pulse",
      privacy: "隐私政策",
      home: "返回首页",
      github: "在 GitHub 提交 Issue",
    },
  },
  en: {
    title: "Get in touch",
    intro:
      "Have a question, suggestion, or bug to report? We would love to hear from you. Here is the best way to reach us.",
    generalHeading: "General inquiries and product feedback",
    general: [
      "For product questions, feature suggestions, or general inquiries, email hello@pulseticker.app. We reply as soon as we can.",
      "For bug reports, please open an issue on GitHub Issues and include your macOS version, Pulse version, and steps to reproduce. A screenshot or screen recording helps a lot.",
    ],
    technicalHeading: "Technical and security",
    technical: [
      "For matters involving data sources, APIs, or security, email sys@pulseticker.app. If you have found a security vulnerability, please do not file a public GitHub Issue — email us directly instead.",
    ],
    responseHeading: "Response time",
    response: [
      "This is an open-source project maintained by a small team. We typically reply to emails and GitHub Issues within 1–3 business days, though we do not guarantee a fixed response time. If your issue has not received a timely reply, please be patient or send a gentle follow-up.",
    ],
    linksHeading: "Other pages",
    links: {
      about: "About Pulse",
      privacy: "Privacy",
      home: "Back to home",
      github: "Open an issue on GitHub",
    },
  },
  ja: {
    title: "お問い合わせ",
    intro:
      "ご質問、ご提案、バグ報告がありましたらお気軽にご連絡ください。以下の方法でアクセスできます。",
    generalHeading: "一般のお問い合わせと製品フィードバック",
    general: [
      "製品に関するご質問、機能のご提案、一般的なお問い合わせは hello@pulseticker.app までメールでお願いします。できるだけ早くご返信します。",
      "バグ報告は GitHub Issues で Issue を開き、macOS のバージョン、Pulse のバージョン、再現手順を含めてください。スクリーンショットや画面録画があると助かります。",
    ],
    technicalHeading: "技術・セキュリティ",
    technical: [
      "データソース、API、セキュリティに関することは sys@pulseticker.app までメールしてください。セキュリティの脆弱性を発見した場合は、公開の GitHub Issue には投稿せず、直接メールでご連絡ください。",
    ],
    responseHeading: "返信までの目安",
    response: [
      "これは小規模チームが保守するオープンソースプロジェクトです。通常は 1〜3 営業日以内にメールと GitHub Issue に返信しますが、固定の応答時間は保証していません。Issue の返信が遅れている場合は、しばらくお待ちいただくか、軽くフォローアップのメールをお送りください。",
    ],
    linksHeading: "その他のページ",
    links: {
      about: "Pulse について",
      privacy: "プライバシー",
      home: "ホームに戻る",
      github: "GitHub で Issue を開く",
    },
  },
  ko: {
    title: "연락하기",
    intro:
      "질문, 제안, 버그 신고가 있으신가요? 여러분의 목소리를 듣고 싶습니다. 아래 방법으로 연락해 주세요.",
    generalHeading: "일반 문의 및 제품 피드백",
    general: [
      "제품 질문, 기능 제안, 일반 문의는 hello@pulseticker.app로 이메일 주세요. 최대한 빨리 답장드립니다.",
      "버그 신고는 GitHub Issues에 Issue를 열고 macOS 버전, Pulse 버전, 재현 단계를 포함해 주세요. 스크린샷이나 화면 녹화가 큰 도움이 됩니다.",
    ],
    technicalHeading: "기술 및 보안",
    technical: [
      "데이터 소스, API, 보안 관련 사항은 sys@pulseticker.app로 이메일 주세요. 보안 취약점을 발견하셨다면 공개 GitHub Issue에 올리지 말고 직접 이메일로 연락해 주세요.",
    ],
    responseHeading: "응답 시간",
    response: [
      "소규모 팀이 유지하는 오픈소스 프로젝트입니다. 보통 1–3 영업일 이내에 이메일과 GitHub Issue에 답장하지만, 고정 응답 시간은 보장하지 않습니다. Issue 답장이 늦어지면 조금만 기다려 주시거나 가볍게 팔로업해 주세요.",
    ],
    linksHeading: "다른 페이지",
    links: {
      about: "Pulse 소개",
      privacy: "개인정보",
      home: "홈으로",
      github: "GitHub에서 Issue 열기",
    },
  },
} as const;

export function ContactPage({ language }: { language: Language }) {
  const copy = translations[language];

  return (
    <main className="info-page">
      <SiteHeader language={language} page="contact" />

      <section className="info-hero shell">
        <h1>{copy.title}</h1>
        <p>{copy.intro}</p>
      </section>

      <section className="info-content shell">
        <div className="info-section">
          <h2>{copy.generalHeading}</h2>
          {copy.general.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>

        <div className="info-section">
          <h2>{copy.technicalHeading}</h2>
          {copy.technical.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>

        <div className="info-section">
          <h2>{copy.responseHeading}</h2>
          {copy.response.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>

        <div className="info-contact-emails">
          <a href={`mailto:${organizationInfo.supportEmail}`}>
            {organizationInfo.supportEmail}
          </a>
          <a href={`mailto:${organizationInfo.technicalEmail}`}>
            {organizationInfo.technicalEmail}
          </a>
        </div>

        <nav className="info-links" aria-label={copy.linksHeading}>
          <Link to={homePath(language)}>{copy.links.home}</Link>
          <Link to={aboutPath(language)}>{copy.links.about}</Link>
          <Link to={privacyPath(language)}>{copy.links.privacy}</Link>
          <a href={repositoryIssuesUrl} target="_blank" rel="noreferrer">
            {copy.links.github}
          </a>
        </nav>
      </section>
    </main>
  );
}
