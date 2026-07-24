# Pulse Website

Pulse 的中英文单页官网，介绍 macOS 菜单栏行情工具并通过 Sites 托管的 R2 提供最新版 DMG 下载，同时保留 GitHub 开源地址。

## 本地运行

需要 Node.js `>=22.13.0`。

```bash
npm install
npm run dev
```

默认通过本地开发服务器预览。页面源码位于 `app/`，静态资源位于 `public/`。

## 检查

```bash
npm run lint
npm test
```

`npm test` 会先生成 Sites 部署构建，再检查中英文内容和主要页面结构。

## 发布

网站使用 Codex Sites 发布，项目配置保存在 `.openai/hosting.json`。
生产环境使用自定义域名 [`www.pulseticker.app`](https://www.pulseticker.app/)。

R2 是 Sites Worker 的内部存储绑定，与访问域名无关；自定义域名由 Sites 路由到同一个 Worker 后，`/download` 会继续使用现有的 `DOWNLOADS` 绑定，不需要为域名单独配置 R2。

安装包使用版本化 R2 对象，官网稳定入口 `/download` 会跳转到带版本参数的下载请求：

```text
/download?version=0.6.1
```

首次访问版本化请求时，Worker 会从固定的 GitHub Release 地址读取文件，校验预期大小与 SHA-256 后写入 Sites 管理的 R2；后续请求直接从 R2 返回。使用查询参数是为了避免 Sites 的静态资源路由拦截带 `.dmg` 后缀的路径。发布新版时需要同步更新 `worker/index.ts` 中的版本、文件名、下载地址、大小和 SHA-256。

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
