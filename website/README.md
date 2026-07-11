# Pulse Website

Pulse 的中英文单页官网，介绍 macOS 菜单栏行情工具并提供最新版下载与 GitHub 开源地址。

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

网站使用 Codex Sites 发布，项目配置保存在 `.openai/hosting.json`。线上下载按钮始终指向 Pulse GitHub 仓库的最新 Release。
