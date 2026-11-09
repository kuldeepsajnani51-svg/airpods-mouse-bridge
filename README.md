# AirPods Mouse Bridge

用 iPhone 读取 AirPods 头部姿态，通过局域网 **UDP** 发给 Windows，用来控制鼠标。

每个包 **48 字节**：6 个小端 `double`，顺序为 `X, Y, Z, Yaw, Pitch, Roll`（位置固定为 0，角度为度）。默认端口 **4242**，与 OpenTrack 的 UDP 协议一致。

本仓库是 iOS 端。签名用你自己的**免费 Apple ID**（不是付费开发者账号），在 Windows 上用 Sideloadly 安装。

> App Store 上没有找到能长时间、免费、并把 AirPods 姿态转发到网络的可靠应用。Safari 也读不到 AirPods 运动数据。

## 你需要准备

| 东西 | 说明 |
|---|---|
| 本 GitHub 仓库设为 **Public** | 公开仓库才能免费用 macOS Actions 分钟数 |
| 免费 Apple ID | 只用来给 App 签名 |
| Windows 电脑 | 安装 [Sideloadly](https://sideloadly.io/) |
| USB 线 | iPhone 连到 Windows |
| iTunes 或 [Apple Devices](https://apps.microsoft.com/detail/9pe56ceeelja) | Sideloadly 需要其中之一 |
| AirPods | 支持空间音频 / 头部追踪（常见为 Pro、Max、第 3 代） |
| iPhone 与电脑在同一 Wi‑Fi | 手机要把数据发到电脑的局域网 IP |

免费 Apple ID 的限制：

- 签名大约 **7 天**过期。过期后用 Sideloadly **再装一次同一个 IPA** 即可，不必重新编译
- 同时大约最多 **3 个**这样安装的 App
- iOS 16 及以上要打开 **开发者模式**

## 一、用 GitHub Actions 编译未签名 IPA

仓库里已经包含源码和 `.github/workflows/build-ipa.yml`。不需要 Mac。

1. 确认仓库是 **Public**。打开 **Actions**，如果页面要求启用，点启用。
2. 左侧选 **Build unsigned IPA** → **Run workflow** → **Run workflow**。推送到 `main` 且改动了 App 源码时也会自动编译。
3. 等运行结束（常见几分钟到十几分钟）。点进绿色的那一次 → 页面底部 **Artifacts** → 下载 `AirPodsMouseBridge-unsigned-ipa`。
4. 解压，得到 `AirPodsMouseBridge-unsigned.ipa`。产物保留 14 天；过期就再运行一次 workflow。

编译在 GitHub 的 **macOS 15** 上完成，使用该镜像默认的 Xcode（`/Applications/Xcode.app`）。macOS 14 的 runner 已于 2026-11-02 停用。

## 二、用 Sideloadly 装到 iPhone

1. 在 Windows 安装并打开 **Sideloadly**。
2. 安装 **iTunes**，或微软商店里的 **Apple Devices**，并打开一次。
3. 用 USB 连接 iPhone，解锁，点「信任此电脑」。
4. 把 `.ipa` 拖进 Sideloadly，选中这台 iPhone，填入**免费 Apple ID**，点 Start。
5. 如果要求双重认证，按提示把验证码填进去。
6. 装完后在 iPhone 打开：**设置 → 通用 → VPN 与设备管理**（有的系统写作「设备管理」）→ 你的 Apple ID → **信任**。
7. **iOS 16 及以上**：**设置 → 隐私与安全性 → 开发者模式** → 打开，按提示重启并确认。

## 三、使用

1. AirPods 连上 iPhone 并戴好。iPhone 和 Windows 连同一个 Wi‑Fi。
2. 打开 App **AirPods Mouse**。
3. 填写电脑的局域网 IP。在 Windows 命令提示符运行 `ipconfig`，看正在上网的那块网卡的 **IPv4 地址**（多半是 `192.168.x.x`）。端口保持 **4242**。
4. 点 **开始推流**。系统会询问「运动与健身」和「本地网络」，都允许。
5. 脸正对屏幕时点 **回中**。Yaw / Pitch / Roll 会接近 0。开始推流时也会把当时的朝向当作正面。
6. 状态里应看到「耳机已连接」和「UDP 就绪」，「已发送包」数字在增加。转头时三个角度会跟着变。
7. 在 Windows 上运行你的接收程序，监听 UDP **4242**。如果你有配套的 `airpods_mouse.py`（不在本仓库里），在那个目录执行：

```bat
python -m venv .venv
.venv\Scripts\activate
pip install keyboard
python airpods_mouse.py
```

看到它开始接收后，转头应能移动光标。Windows 防火墙需要放行 **UDP 4242**。

推流时可以打开「保持屏幕常亮」。关掉屏幕或切走 App 后，iOS 会暂停发送；回到 App 会继续。

## 四、大约 7 天后

图标变灰或提示未验证、无法打开时：用 Sideloadly 和**同一个 Apple ID** 再安装一次这个 IPA。也可以改用 [AltStore](https://altstore.io/)，在同一 Wi‑Fi 下用 AltServer 刷新。

## 源码

| 文件 | 作用 |
|---|---|
| `project.yml` | XcodeGen 工程。部署目标 iOS 15，签名关闭，方便打未签名包 |
| `AirPodsMouseBridge/*.swift` | 界面、`CMHeadphoneMotionManager` 姿态、UDP 发送、回中 |
| `AirPodsMouseBridge/Info.plist` | 运动与健身、本地网络用途说明（缺运动说明时，一启动传感器 App 会崩溃） |
| `.github/workflows/build-ipa.yml` | 在 macOS 15 上生成未签名 IPA |

不包含付费 Apple Developer 证书。签名由 Sideloadly 用你的免费 Apple ID 完成。

## 界面里有什么

- 电脑 IP 和端口
- 开始 / 停止
- 回中
- 实时 Yaw、Pitch、Roll
- 耳机是否连上、UDP 是否就绪、已发送包数量、错误说明
