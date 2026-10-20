# macOS 打包与发布

## 面向用户

发布包为 macOS 14+ 的 Universal App，同时包含 arm64 和 x86_64，适用于 Apple Silicon 与 Intel Mac。DMG 内有「贴边.app」、Applications 快捷方式和安装说明；ZIP 可作为另一种下载方式。

把 App 拖到 Applications 后打开。也支持其他本机安装文件夹和重命名；MCP 配置窗口从当前运行 App 的 `Bundle.main.bundleURL` 计算 helper 位置，用户移动 App 后重新复制 Prompt 即可。不要把磁盘映像或 AppTranslocation 临时路径写成长期 MCP 配置。

App 的便签数据保存在用户 Application Support 下，更新 App 不覆盖便签。登录项由 macOS 管理，不随安装包自动开启。

## 开发构建

```bash
./scripts/build-app.sh debug
./scripts/build-app.sh release --universal
```

默认输出 `dist/贴边.app`，开发构建使用 ad-hoc 签名。可用 `--output` 指定其他路径，或用 `--identity` / `CODESIGN_IDENTITY` 指定证书。构建写入 `EdgePeekSourceCommit` 和 `EdgePeekSourceDirty`，签名完成后才替换旧的生成目录。

图标是原生 AppKit 绘图，可复现：

```bash
./scripts/make-icon.sh
```

检查 1024px 主图、透明边缘、16/32/64px 缩略图和 `iconutil` 标准尺寸。安装包仅复制明确列出的运行时资源与字体授权，不复制开发配置或凭据。

## 发布检查

1. 完成相关文档、`swift test`、`python3 -m unittest discover -s scripts -p 'test_*.py'` 和本轮 `$simplify`。
2. 提交所有本任务改动，合入 origin 实际主分支并推送。重新 fetch，确认任务分支被远端主分支包含，且本地主分支、远端主分支相同、工作区干净。
3. 从这个已推送的主分支 commit 打包。脚本再次检查干净状态及 origin 的实时 HEAD；未推送、未合并或脏目录会拒绝发布构建。
4. 发布包必须使用 Developer ID Application 证书、Hardened Runtime、安全时间戳和 Apple 公证。不能把开发 ad-hoc 包当成可分发版本。

公证凭据只通过环境提供：`NOTARY_PROFILE`，或 `NOTARY_KEY_PATH` / `NOTARY_KEY_ID` / `NOTARY_ISSUER`。私钥不写进仓库、日志或包内。

```bash
python3 scripts/package_release.py \
  --identity 'Developer ID Application: Your Name (TEAMID)' \
  --output dist/releases/1.1.0
```

脚本先构建和签名 Universal App，公证并 staple App，再生成 ZIP 和 DMG，签名、公证并 staple DMG。每次公证必须读到 `Accepted`，随后执行 stapler 和 Gatekeeper 检查；相同目录已有发布文件时停止，避免覆盖已有版本。输出 `release-proof.json` 和 `SHA256SUMS.txt`，记录源码 SHA、架构、公证提交 ID 和文件哈希。

打包不自动创建 GitHub Release。得到用户发布授权后，先确认目标仓库仍为 private，再用实际源码 SHA 创建 tag / Release，上传 DMG、ZIP、proof 和校验文件。发布后重新下载资产，比较 SHA-256，挂载 DMG 核对 App 签名、架构、源码 SHA、Applications 快捷方式及安装说明，最后卸载映像。

本机安装到 `/Applications/贴边.app` 时先正常退出旧进程，再安装同一发布产物。验证运行进程的实际可执行路径、Info.plist 中的源码 SHA，以及安装位置下 MCP 的 initialize / tools/list。不要从源码工作区另建一个包冒充刚发布的产物。

## 发布文案检查

此次发布的 Lever / Position / Turn：

- Lever：用签名、公证、可核对的构建来源和本机存储建立真实信任，不使用虚构评价或用户数。
- Position：住在屏幕边缘、让 Agent 也能读写的本地 Mac 便签。
- Turn：用户随手记下想法后，无需切换 App，移到边缘就能找回；复制一段 Prompt 就能让 Agent 连接现有本地便签。
