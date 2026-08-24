# Pulse Website

Pulse 的多语言单页官网（中文 / English / 日本語），介绍 macOS 菜单栏行情工具，并通过 Cloudflare Workers 绑定的 R2 提供最新版 DMG 下载，同时保留 GitHub 开源地址。

技术栈：TanStack Start + Vite + `@cloudflare/vite-plugin`，部署为 Cloudflare Worker（2026-07-30 从 vinext/ChatGPT Sites 脚手架迁出）。

## 目录结构

- `src/routes/`：页面路由（`__root.tsx` 文档骨架与全站 meta / Umami，`index.tsx` 首页，`changelog.tsx` 更新日志）。
- `src/components/`：交互组件（自选列表演示、Umami 下载事件）。
- `src/data/releases.ts`：更新日志数据（`zh` / `en` / `ja` 三语，均为必填），发版时在此追加条目。
- `src/styles/globals.css`：全站样式（Tailwind 仅用于 preflight，版式为手写 CSS）。
- `src/server.ts`：Worker 入口，先处理 `/download` 再交给 TanStack Start SSR。
- `src/download.ts`：R2 下载镜像逻辑与当前版本元数据。
- `src/routeTree.gen.ts`：由 TanStack Start 插件生成，不入库。
- `wrangler.jsonc`：Worker 配置（R2 绑定、自定义域名路由）。

## 本地运行

需要 Node.js `>=22.13.0`。

```bash
npm install
npm run dev
```

`npm run dev` 通过 Vite + workerd 本地运行，包含 `/download` 路由（本地 R2 为空时会尝试回源 GitHub）。

## 检查

```bash
npm run lint
npx tsc --noEmit
npm test
```

`npm test` 会先执行生产构建，再直接加载 `dist/server/index.js` 对首页、更新日志的 SSR HTML 和 `/download` 行为做断言。

## 发布

网站部署在 Cloudflare Workers（Worker 名 `pulse-website`）。推送 `main` 后由 Cloudflare Git 集成自动构建和部署；正常发版不运行单独的部署命令。`npm run deploy` 仅保留为需要人工接管时的应急命令。

生产环境使用自定义域名 [`www.pulseticker.app`](https://www.pulseticker.app/)，预览地址
`https://pulse-website.fatwang2.workers.dev`。

`/download` 使用 Worker 绑定的 R2 桶 `pulse-downloads`（绑定名 `DOWNLOADS`），与访问域名无关。

安装包使用版本化 R2 对象，官网稳定入口 `/download` 会跳转到带版本参数的下载请求：

```text
/download?version=<version>
```

首次访问版本化请求时，Worker 会从固定的 GitHub Release 地址读取文件，校验预期大小与 SHA-256 后写入 R2；后续请求直接从 R2 返回。**发布新版时先在 `src/data/releases.ts` 追加更新日志；GitHub Release 生成 DMG 后，再用实际文件的版本、文件名、下载地址、大小和 SHA-256 更新 `src/download.ts`，推送 `main` 触发官网部署。**

## 行情数据源标识

官网展示的品牌标识仅用于说明 Pulse 使用的行情数据来源，不代表合作、赞助或背书。商标及品牌标识归各自权利人所有。

- Longbridge：当前 Longbridge 香港官网品牌素材
  `https://assets.wbrks.com/assets/logo/light/hk.png`
- Binance：Wikimedia Commons 收录的 Binance 标准标识
  `https://upload.wikimedia.org/wikipedia/commons/1/12/Binance_logo.svg`
- Tencent：腾讯官方媒体资源库蓝色标准标识
  `https://www.tencent.com/wp-content/uploads/2022/12/01_Tencent_Standard-Logo.png`
- Yahoo Finance：Yahoo Inc. 提供、由 Wikimedia Commons 收录的标准标识
  `https://upload.wikimedia.org/wikipedia/commons/9/9f/Yahoo%21_Finance_logo.svg`

## 访问分析

官网使用自托管的 [Umami](https://umami.is)（实例 `umami.fatwang2.com`）进行隐私优先的
无 Cookie 访问分析，Website ID 为 `bf5c4531-e265-4858-afd9-ed014426038d`。

- 页面访问、来源等基础指标由 Umami 自动收集，无需 Cookie，不跨站追踪。
- 所有指向 `/download` 的点击额外记录为 `file_download` 事件，并附带 DMG 文件类型、
  链接文字和落地 URL。
- 跟踪脚本以 `<script defer>` 注入 `<head>`，SPA 内的路由切换由 Umami 自动捕获。
