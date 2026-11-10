# Ralinfr Xbox Store 构建验证记录

检查日期 2026-11-10（中国标准时间）。源码基线为上游 `main` 的 `f85d0ef9b48d4a272d42ded2b060a4d985a70197`。上游同 SHA 的 [Windows 侧载 CI](https://github.com/thedavidweng/wiliwili-uwp/actions/runs/25102773694) 在公开 API 中显示成功。

## 本次状态

实际执行了源码下载、依赖检出、mpv 校验、PowerShell 语法解析、工作流 lint、静态清单检查和验证脚本的合成测试。Linux 上执行商店构建入口时，Windows 工具链检查返回退出码 1。GitHub API 的账户检查返回退出码 4，CLI 没有已登录身份，无法创建用户 fork、推送或启动 Windows runner。Partner Center 页面请求发生远端连接失败，产品后台和设备可用性待账号内核实。

| 项目 | 配置或实测 | 结果 |
| --- | --- | --- |
| Package Name | `Ralinfr.BilibiliforXbox` | 源清单已核对 |
| Publisher | `CN=51C44227-390E-4AC6-ACAA-ABF4CEE83F30` | 源清单已核对 |
| PublisherDisplayName | `Ralinfr` | 源清单已核对 |
| Package Family Name | `Ralinfr.BilibiliforXbox_14gjq6q7k34m8` | 从源清单 Name 和 Publisher 推导一致 |
| Store ID | `9N6TDF2N4JD5` | 用户提供，后台待核对 |
| 包版本 | `1.6.0.0` | 默认值，需和现有商店版本比较 |
| 架构及配置 | x64 / Release | 源清单和构建参数已核对 |
| Windows.Universal | 最低 `10.0.17763.0`，MaxVersionTested `10.0.22621.0` | 源清单已核对 |
| Windows.Xbox | 最低 `10.0.19041.0`，MaxVersionTested `10.0.22621.0` | 源清单已核对 |
| 应用入口 | `App` / `wiliwili-uwp.exe` / `wiliwili-uwp.App` | 保留原生 UWP 入口；Xbox 启动待测 |
| 最终文件、路径、大小、SHA256 | 尚无最终包 | 由成功运行的 CI 写入 `verification.json` |
| Windows SDK 和认证 | 待执行 MakeAppx、WACK 和真机测试 | 合成测试使用替身解包器，覆盖脚本的数据检查 |

## 固定依赖

| 依赖 | 固定对象或校验 | 实际检查 |
| --- | --- | --- |
| borealis `winrt-dev` | `789b230cb4e50ff2098ae872a6bfe3f1d835f25b` | 从 `ikas-mc/borealis` 检出 |
| wiliwili `winrt-dev` | `ff43110e224c822f527f8c3dd0fb96eba9c3c827` | 原 fork 返回 404，从 `xfangfang/wiliwili` 获取同一 Git 对象 |
| libpdr | `b24fb9d0e761b716dddbfb45564750a9b6523966` | Git 子模块检出 |
| pystring | `7d16bc814ccb4cad03c300dcb77440034caa84f7` | Git 子模块检出 |
| mongoose | `4328842400370f62d00b6a6b23f1cbe0cded4073` | Git 子模块检出 |
| vcpkg registry 和 bootstrap | `52f5569a8e867859fac967c1e3f10ca0a8a3cc39` | 从微软 Git 仓库获取原对象，原配置是 tag，解析为同一树的提交 `c3867e714dd3a51c272826eea77267876517ed99`，构建使用该提交 |
| `x64-uwp-mpv.zip` | `82f8ce29700bf2c586d64c991f602b78c3e9a560c9094f07572db7f7e3ab7cef` | 下载 20,372,288 字节，SHA256 与发布元数据及上游脚本一致，ZIP CRC 通过 |

CMake、Visual Studio 及 runner 镜像补丁版本会随宿主更新，日志会记录实际工具版本。本工程固定应用源码和依赖版本，未验证二进制逐字节可复现。解包脚本运行 Windows SDK MakeAppx，检查 SHA256 block map，校验应用与两个 mpv DLL 的 x64 PE 文件头，并保存最终包的清单。此项检查与 WACK 和设备运行测试是不同的阶段。

## 设备与能力检查

- 固定 borealis 的 WinRT 实现使用 CoreApplication、D3D11 和 Xbox 设备分支。wiliwili 的原生 `wWinMain` 调用 WinRT 入口。两个 mpv DLL 的 PE 机器类型为 x64，导入 D3D、Media Foundation、UWP VC Runtime 等接口。需在成包后通过 WACK 检查 API，并在 Xbox 上核对 VCLibs 框架依赖、设备启动、控制器输入、前后台恢复及持续播放。
- 商店清单保留联网和后台媒体能力，移除了 PhoneIdentity、桌面执行别名、入站网络能力及 `expandedResources`、`hevcPlayback`。源码检查未发现应用监听服务器或显式申请扩展资源。上游播放器含 HEVC 和 D3D 硬解路径。Xbox 的专用 4K 权限具有资源与后台限制，本候选版按普通媒体应用验证，首轮实测建议覆盖 AVC/H.264 1080p；HEVC、HDR 和 4K 的实际行为待测。[Microsoft 能力声明](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/app-capability-declarations) · [Xbox HEVC/4K 说明](https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/hevc-xbox)
- 商店构建对固定 wiliwili 源码使用一个单独生成的配置源文件，将 UWP 的 TLS 验证默认值设为开启。默认网络请求因而使用 HTTPS。保留上游的设置界面。发布前需在 Windows 和 Xbox 实测证书链、无效证书拒绝、Bilibili 登录及播放器请求。

## 品牌与发布前许可核对

商店版的包内显示名称为 `wiliwili (Ralinfr)`，包用新绘制的播放图形替换原清单引用的图标和磁贴。应用内容归属与原上游 README 一并保留。商店名称以 Partner Center 实际保留名称为准，清楚标注第三方客户端，发布前核对应用内上游图像、字体、第三方服务及截图的使用权。[Microsoft Store 政策](https://learn.microsoft.com/windows/apps/publish/store-policies)

保留 `LICENSE` 中的 GPL-3.0 文本及 xfangfang、ikas-mc、thedavidweng 和贡献者归属。分发二进制前，按适用许可证向接收者提供实际所分发版本的对应源码、改动、构建脚本和通知，包括 mpv、其静态链接组件和适用的第三方资源。下载包中的 `mpv-2.dll` 自报 `mpv v0.40.0-dev-g5c5e0cd94` 和 FFmpeg 7.1.1。仓库里存在另一套构建笔记，不能作为此二进制的完整对应源码。已检出 DLL 自报版本对应的 [mpv UWP 提交](https://github.com/mpv-player/mpv/commit/5c5e0cd941d2282bbd1d0e887082c5a3b093f48d)。DLL 中记录的 FFmpeg 构建仓库返回 404，静态链接依赖的完整构建配方及对应源码仍待核齐。这项核对应在向私人受众分发前完成。[GPL-3.0 正文](https://www.gnu.org/licenses/gpl-3.0.html) · [mpv 原始发布记录](https://github.com/ikas-mc/wiliwili-uwp-poc/releases/tag/0.4)
