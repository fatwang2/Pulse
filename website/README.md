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

安装包使用版本化 R2 对象路径，官网稳定入口 `/download` 会跳转到当前版本：

```text
/downloads/v0.4.0/Pulse-0.4.0.dmg
```

首次访问版本化地址时，Worker 会从固定的 GitHub Release 地址读取文件，校验预期大小与 SHA-256 后写入 Sites 管理的 R2；后续请求直接从 R2 返回。发布新版时需要同步更新 `worker/index.ts` 中的版本、文件名、下载地址、大小和 SHA-256。
