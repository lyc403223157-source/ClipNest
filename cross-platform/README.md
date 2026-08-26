# ClipNest for Windows and Linux

ClipNest 的 Windows/Linux MVP 使用 Tauri 2、Rust 和系统 WebView。macOS 使用仓库根目录的原生 AppKit 版本。

在 AI 工作流里，提示词、参考资料和图片经常需要在多个应用之间反复搬运。ClipNest 把这些高频素材放进一个随时可唤起的轻量面板，让“找到并粘贴上一段 Prompt”变成一次键盘操作。

## 交互

- `Alt+V` 打开快速面板，保留 `Ctrl+V` 的系统直接粘贴行为。
- 每次打开回到“最近”的第一条。
- 左右方向键切换标签，上下方向键选择条目，Enter 或数字键 1–5 粘贴，Esc 关闭。
- 面板按五行高度展示，历史和自定义组不限制保存条数，超出后滚动浏览。
- 文本和 URL 只保存在本机 WebView 的应用数据目录，不上传网络。
- 面板优先显示在鼠标附近；粘贴时隐藏面板并恢复到此前应用。

## 平台说明

- Windows 使用低级键盘 Hook，无需辅助功能授权。
- Linux 当前以 X11 为主要目标；Wayland 是否允许全局快捷键和模拟输入取决于桌面环境与安全策略。
- 当前跨平台 MVP 支持文本和 URL；截图历史仍由 macOS 原生版提供。

## 本地测试

```sh
npm ci
npm test
npm run check
```

## 本地构建

安装 Rust 和对应平台的 [Tauri 2 prerequisites](https://v2.tauri.app/start/prerequisites/) 后运行：

```sh
npm run tauri build
```

GitHub Actions 会在原生 Windows、Ubuntu 和 macOS runner 上执行测试与构建；只有三个平台全部成功，版本标签才会生成 Release。
