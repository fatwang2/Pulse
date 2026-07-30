# Pulse Website

Pulse 的中英文单页官网，介绍 macOS 菜单栏行情工具，并通过 Cloudflare Workers 绑定的 R2 提供最新版 DMG 下载，同时保留 GitHub 开源地址。

技术栈：TanStack Start + Vite + `@cloudflare/vite-plugin`，部署为 Cloudflare Worker（2026-07-30 从 vinext/ChatGPT Sites 脚手架迁出）。

## 目录结构

- `src/routes/`：页面路由（`__root.tsx` 文档骨架与全站 meta / GA，`index.tsx` 首页，`changelog.tsx` 更新日志）。
- `src/components/`：交互组件（自选列表演示、GA 下载事件）。
- `src/data/releases.ts`：更新日志数据（中英双语），发版时在此追加条目。
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

网站部署在 Cloudflare Workers（Worker 名 `pulse-website`）：

```bash
npm run deploy
```

等价于 `vite build && wrangler deploy`（`@cloudflare/vite-plugin` 会在 `dist/` 下生成最终 wrangler 配置，`wrangler deploy` 通过 `.wrangler/deploy/config.json` 自动指向它）。

生产环境使用自定义域名 [`www.pulseticker.app`](https://www.pulseticker.app/)，预览地址
`https://pulse-website.fatwang2.workers.dev`。

`/download` 使用 Worker 绑定的 R2 桶 `pulse-downloads`（绑定名 `DOWNLOADS`），与访问域名无关。

安装包使用版本化 R2 对象，官网稳定入口 `/download` 会跳转到带版本参数的下载请求：

```text
/download?version=0.8.1
```

首次访问版本化请求时，Worker 会从固定的 GitHub Release 地址读取文件，校验预期大小与 SHA-256 后写入 R2；后续请求直接从 R2 返回。**发布新版时需要同步更新 `src/download.ts` 中的版本、文件名、下载地址、大小和 SHA-256，并在 `src/data/releases.ts` 中追加更新日志。**

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

官网使用独立的 GA4 Property `Pulse`（Property ID `546939165`）和 Web 数据流
`Pulse Website`（Measurement ID `G-J9GLF06LPP`）。

- 页面访问、来源、滚动和站外点击由 GA4 与增强型衡量记录。
- 所有指向 `/download` 的点击额外记录为 `file_download`，并附带 DMG 文件类型、
  链接文字和落地 URL。
- 默认拒绝 Analytics 与广告存储，并关闭 Google Signals 和广告个性化信号；
  GA4 以不写入这些 Cookie 的方式接收聚合测量事件。
