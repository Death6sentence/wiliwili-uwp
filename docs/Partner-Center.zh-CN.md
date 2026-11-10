# Partner Center 提交草稿与 Xbox 零售模式安装

这份操作清单用于 Store ID `9N6TDF2N4JD5`。当前交付已准备离线草稿，后台设备勾选状态待实际登录核对。提交认证和发布需由产品所有者确认。

## 1. 打开正确产品

在 [Partner Center](https://partner.microsoft.com/dashboard) 中进入 **应用和游戏**，打开该 Store ID 对应的产品，进入 **产品管理 → 产品标识**（部分界面显示 **应用标识**）。核对 Store ID、Package/Identity/Name、Publisher、PublisherDisplayName 和 PFN。当前配置见 [验证记录](Verification.zh-CN.md)。检查历史提交的受众状态、最高包版本及已保留产品名称，再新建提交草稿。

## 2. 核对 x64 程序包与设备系列

在 **程序包** 上传 Windows CI 生成的 `.appxupload` 或 `.msixupload`，同时核对 CI 的 `AppxManifest.xml`、`verification.json` 和 `SHA256SUMS.txt`。微软文档还列出了原始 APPX/MSIX 和 bundle 格式，若 CI 只生成这些格式，先核对具体失败原因和该产品后台的验证结果。

上传完成后打开 **设备系列可用性**，查看 **Windows 10 Xbox** 是否可选并勾选，确认实际分配给 Xbox 的最高版本是本次 x64 包。按发布范围决定 Windows 桌面等其他设备选项。若 Xbox 选项缺失、禁用或指向另一包，先检查包身份、架构、目标设备系列、SDK、产品类型及资格。微软要求 Xbox 启动包为 x64 或 neutral，且由 Windows SDK 14393 或更高版本编译。[上传 MSIX 应用包](https://learn.microsoft.com/zh-cn/windows/apps/publish/publish-your-app/msix/upload-app-packages)

## 3. 设置私人受众

在 **定价和可用性 → 可见性 → 受众** 选择 **私人受众**，选择或创建已知用户组，填入测试者用于登录 Microsoft Store 的个人 Microsoft 账户邮箱。测试者的主机地区需在产品选择的可用市场内。按需设置可发现性，确保草稿中的定时公开选项未启用，并记录该提交提供的需登录商店链接。若该产品曾以公共受众提交，微软文档说明后续提交不能改为私人受众。先确认此 Store ID 的历史状态。[MSIX 应用可见性](https://learn.microsoft.com/zh-cn/windows/apps/publish/publish-your-app/msix/visibility-options)

## 4. 补全资料并停在草稿

- **商店一览**填写实际保留的产品名称。简介可用「基于 wiliwili 的第三方 B 站客户端，适配 Xbox 手柄操作。发布者 Ralinfr。」图像和截图使用自己有权使用的素材，准确体现测试过的功能。
- 填写 **属性**、**年龄分级**、支持联系信息及隐私策略。准确说明登录、Cookie、账号数据和网络请求的处理。准备可访问的 GPL 对应源码和第三方归属。当前 mpv 对应源码核对和 TLS 证书验证实测是发布前待办，详见验证记录。
- **认证说明**写明手柄操作、无需账号可测试的功能、需要账号的步骤、网络前置条件及已实测的画质范围。把未经验证的 HEVC、HDR、4K 和机型行为留在待测项。私人受众仍会经过认证。完成包和真机验证、资料及权限确认后，再由产品所有者批准提交。[Microsoft Store 政策](https://learn.microsoft.com/windows/apps/publish/store-policies) · [打包 MSIX 应用](https://learn.microsoft.com/zh-cn/windows/msix/package/packaging-uwp-apps)

## 5. 在 Xbox Series S 零售模式安装

认证通过并发布给私人受众后，在零售模式 Xbox 使用已加入组的同一 Microsoft 个人账户打开 Microsoft Store。若允许搜索，在主机商店搜索实际保留的产品名称。也可在登录同一账户的设备打开 Partner Center 给出的认证链接，先尝试从产品页获取，再在 Xbox 商店或 **我的游戏和应用 → 完整库** 中找已获取的应用。是否提供跨设备安装按钮，以该产品页面为准。若主机仍找不到产品，依次核对账号、市场、Xbox 设备系列、提交发布状态及分发是否已经生效。应用应由 Microsoft Store 下发并安装。

首轮 Xbox 测试记录主机 OS、实际包版本、冷启动、手柄焦点与返回、搜索、登录、AVC 1080p、暂停与恢复、后台行为以及连续播放稳定性。
