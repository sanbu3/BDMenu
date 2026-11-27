# README 媒体来源

- 采集日期：2026-11-27；应用：本地签名安装的 BDMenu 2.6.0。
- `../images/quick-panel.png`、`displays.png`、`keyboard.png`、`automation.png`：真实应用窗口截图。
- `../images/appearance-dark.png`、`automation-dark.png`：临时切换 BDMenu 自身外观后采集，随后恢复跟随系统。
- `settings-demo.mp4`：macOS 原生窗口录屏，来源仅 BDMenu 窗口；截取开头约 9 秒并压缩，无音轨，展示自动化与应用设置入口。它不是窗口适配或自动降载的功能演示。
- `../images/settings-demo.gif`：同一录屏导出的 5 fps、560 px 宽循环预览，便于 GitHub 内嵌展示。不是重新绘制的界面。
- `../images/hero.png`：应用图标、真实窗口截图与标题的静态排版；生成脚本为 `../scripts/build_hero.py`，需要 Pillow 和本机中文字体。
- `../images/adaptive-2.7.png`：2026-11-28 安装的 2.7.0 自适应设置窗口截图。
- `../images/app-icon.png`：来自仓库构建的应用图标。
- `../images/brightness-hud.png`：仓库既有旧版亮度提示素材，未作为本次首屏展示。

截图中的参数属于当时的用户自定义设置：默认角度阈值仍为 65° / 80°，图中 61° / 87° 不代表默认值。GPU 百分比是瞬时整机读数，不用于性能或功耗结论。显示器名称是设备报告名称，不包含个人文件、账户、聊天或密码。

重新采集时优先录制单个应用窗口，避免拍入桌面、其他窗口或通知；不记录系统授权或密码输入过程。更新媒体时同步核对 README、指南与代码版本。
