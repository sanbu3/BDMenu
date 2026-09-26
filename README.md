# BDMenu

Mac 菜单栏显示器管理器 —— BetterDisplay 的免费开源替代(日常功能)。

一个常驻菜单栏的小工具,把 macOS 藏起来的显示器控制能力全部放回菜单栏:开关任意屏幕、内建/外置亮度、DDC 音量与输入源、分辨率切换、镜像、主屏切换,以及接入外置屏后自动关闭内建屏的工作流。

## 功能

- **菜单栏面板**:点按菜单栏图标弹出,所有操作即点即生效
- **开关任意显示器**:真正断开(内核级 disable),不是简单的亮度 0;断开后随时可软件恢复
- **亮度**:
  - 内建屏:DisplayServices 原生亮度
  - 外置屏:DDC/CI 硬件亮度(通过 m1ddc);DDC 不可用时自动降级为 gamma 软件调光(界面会显示「软件调光」标记)
- **亮度键跟随鼠标**:按 Mac 键盘的亮度键(F1/F2),调节的是鼠标所在的那块屏 —— 鼠标在外置屏就调外置屏(带 HUD 百分比提示),在内建屏就走系统原生调节。⇧⌥+亮度键 = 精细步进(需要辅助功能权限,面板内一键授权)
- **外置屏控制**:音量(DDC)、输入源切换(DP/HDMI/USB-C)、分辨率/刷新率/HiDPI 切换(displayplacer)
- **自动工作流**(核心):开启后
  - 接入外置屏 → 自动关闭内建屏,外置屏成为主屏(Dock/菜单栏随之迁移)
  - 断开外置屏 → 自动恢复内建屏与之前的亮度
  - 布局自动记忆、重连自动还原,无需手动保存
  - 含故障保护:拔线时即使内建屏处于关闭状态也会自动找回(过滤 macOS 生成的虚拟显示器,防止黑屏)
- **镜像模式**、**设为主屏**、**登录时启动**(SMAppService)
- **全部点亮**:极端情况(两块屏都被关)一键恢复

## 系统要求

- macOS 14+ (Sonoma),Apple Silicon
- 外置屏 DDC 亮度需要 USB-C/DisplayPort 连接(HDMI 无法走 DDC,自动降级为软件调光)

## 安装与构建

```bash
./build.sh                     # 生成 build/BDMenu.app(含图标、签名)
cp -R build/BDMenu.app /Applications/
open /Applications/BDMenu.app
```

登录时启动:面板内打开「登录时启动」开关即可,或到 系统设置 → 通用 → 登录项 手动添加。

## 工作原理

| 能力 | 实现 |
| --- | --- |
| 显示器开关 | SkyLight 私有 API `CGSGetDisplayList` + `CGSConfigureDisplayEnabled` |
| 内建屏亮度 | `DisplayServicesGet/SetBrightness` |
| 外置屏亮度/音量/输入源 | 内置 m1ddc(DDC/CI over IOAVService) |
| 分辨率/排列/镜像/主屏 | 内置 displayplacer |
| 显示器信息 | `CoreDisplay_DisplayCreateInfoDictionary`(名称/UUID/虚拟屏识别) |
| 热插拔检测 | `CGDisplayRegisterReconfigurationCallback` |

## 借鉴的开源项目

- [Crisp](https://github.com/didriksg/Crisp) — BetterDisplay 开源替代,UI 精简思路、软件调光降级
- [Lunar](https://github.com/alin23/Lunar) — DDC 与黑屏(blackout)方案
- [MonitorControl](https://github.com/MonitorControl/MonitorControl) — 菜单栏 DDC 控制
- [displaydeck](https://github.com/pyxis3-ai/displaydeck) — 自动关闭内建屏 + 幻影屏故障保护
- [OpenDisplay](https://github.com/aquitaine/OpenDisplay) — 受保护布局(热插拔后自动还原)
- [displayplacer](https://github.com/jakehilborn/displayplacer) · [m1ddc](https://github.com/waydabber/m1ddc) — 内置工具(MIT)

## 项目结构

```
Package.swift          SwiftPM 工程
Sources/BDMenu/        主程序(SwiftUI + MenuBarExtra)
bin/                   内置的 m1ddc / displayplacer 二进制
Info.plist             LSUIElement 菜单栏应用
make_icon.swift        图标渲染脚本
make_icon.sh           图标 → icns
build.sh               一键构建 .app
cli/                   命令行工具 bds(可选,终端里同样能力)
```

## License

[MIT](LICENSE)
