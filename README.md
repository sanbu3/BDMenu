# BDMenu

Mac 菜单栏显示器管理器 —— BetterDisplay 的免费开源替代(日常功能)。

一个常驻菜单栏的小工具,把常用显示器控制集中到菜单栏:开关任意屏幕、内建/外置亮度、DDC 音量与输入源、分辨率切换、镜像、主屏切换,以及接入外置屏后自动关闭内建屏的工作流。

## 功能

- **菜单栏面板**:点按菜单栏图标弹出,所有操作即点即生效
- **开关任意显示器**:通过 SkyLight 关闭/重新启用显示器；保留至少一块在线实体屏，实际支持取决于 macOS
- **亮度**:
  - 内建屏:DisplayServices 原生亮度
  - 外置屏:DDC/CI 硬件亮度(通过 m1ddc);DDC 检测不可用时使用 gamma 软件调光（显示状态，正常退出恢复原色彩曲线）
- **亮度键跟随鼠标**:按 Mac 键盘的亮度功能键,调节的是鼠标所在的那块屏 —— 鼠标在外置屏就调外置屏(带 HUD 百分比提示),在内建屏就走系统原生调节。⇧⌥+亮度键 = 精细步进(需要辅助功能权限,面板内一键授权)
- **外置屏控制**:音量(DDC)、输入源切换(DP/HDMI/USB-C)、分辨率/刷新率/HiDPI 切换(displayplacer)
- **自动工作流**(核心):开启后
  - 接入外置屏 → 自动关闭内建屏,外置屏成为主屏(Dock/菜单栏随之迁移)
  - 断开外置屏 → 自动恢复内建屏与之前的亮度
  - 布局自动记忆、重连自动还原,无需手动保存
  - 含恢复保护：拔出最后一块外置屏时尝试恢复已识别的内建屏，过滤已标记的虚拟屏/AirPlay；不猜测显示器 ID
- **镜像模式**、**设为主屏**、**登录时启动**(SMAppService)
- **全部点亮**：恢复可识别实体屏及亮度，同时暂停自动工作流

## 系统要求

- macOS 14+（Sonoma）、Apple Silicon；构建需要 Xcode Command Line Tools
- 外置屏 DDC 支持取决于 Mac、显示器、接口、线材及内置 m1ddc 版本；USB-C/DisplayPort 是常见路径，不能笼统认为所有 HDMI 都不支持

## 安装与构建

```bash
./build.sh       # 使用固定签名身份，生成 build/BDMenu.app
./install.sh     # 安装/更新到 /Applications/BDMenu.app，并启动
```

首次构建会选择唯一的 Apple Development（或 Developer ID Application）身份，并记在仅本地的 `.signing-identity` 中。没有证书或存在多个候选时会停止并给出指引，不会静默退回临时签名。可显式选择：

```bash
security find-identity -v -p codesigning
CODE_SIGN_IDENTITY='你的证书 SHA-1' ./build.sh
```

如果没有可用身份，可在 Xcode → Settings → Accounts → Manage Certificates 中配置 Apple Development 证书。测试/CI 可以使用 `./build.sh --adhoc`，但此构建不保证更新后保留辅助功能授权。

**从旧版本升级**：安装完成后，在系统设置 → 隐私与安全性 → 辅助功能中移除旧 BDMenu，重新添加并允许 `/Applications/BDMenu.app`。面板会自动更新授权状态，必要时退出并重新启动。签名身份兼容且 Bundle ID 不变时通常可延续授权，但不能保证永久有效。

登录时启动：在面板中打开开关；需要审批时会进入系统登录项设置。

## 1.2 修复与优化

- 权限检查、显示器回调、亮度键监听跟随应用生命周期，面板关闭时仍有效；授权中、监听失败、正常启用分别显示。
- 支持系统亮度媒体键和亮度虚拟键码，处理按键释放和事件监听被系统暂停的情况；内建屏保留系统原生处理。
- 外部命令在后台串行执行，具有超时、退出码和错误处理；大量 stdout/stderr 不会把进程卡死。
- 每块显示器独立管理亮度、音量、输入源与模式；连续调节合并为最新值，按设备最大值转换百分比。
- 修复分辨率编号全部被解析为 0 的问题，保留旋转、负坐标和关闭状态；切换主屏保持相对布局。
- 按连接的显示器 UUID 集合保存/恢复布局，拒绝向不同显示器组合套用旧配置。
- 软件调光基于原有色彩曲线，正常退出还原；一次 DDC 写入失败不会立即叠加软件调光。
- 构建完成并验证签名后才替换旧产物；安装在固定路径，检测签名身份变化。
- 附带 CLI 修复坐标分隔符丢失、主屏位置/旋转丢失，移除配置恢复中的 `eval`，支持包含空格的工具路径。

验证方式、一次性授权迁移和实机验收项目见 [docs/VALIDATION.md](docs/VALIDATION.md)。

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
Sources/BDMenu/        主程序、权限与显示控制（SwiftUI + MenuBarExtra）
Sources/DisplayCore/   可测试的布局解析与子进程执行
Tests/                回归测试
bin/                   内置的 m1ddc / displayplacer 二进制
Info.plist             LSUIElement 菜单栏应用
make_icon.swift        图标渲染脚本
make_icon.sh           图标 → icns
build.sh               固定签名构建 .app
install.sh             安装与更新
cli/                   命令行工具 bds(可选,终端里同样能力)
```

## License

[MIT](LICENSE)
