# 用 Skill 操作贴边

贴边随 App 打包本地 Skill 和 Swift CLI，替代原来的 MCP：

```text
贴边.app/Contents/Resources/Skills/edgepeek/SKILL.md
贴边.app/Contents/MacOS/edgepeek-cli
```

Skill 按需加载说明，由单次调用的 CLI 直接读写 App 使用的同一份 JSON。无后台服务、端口、网络请求或额外依赖；App 未运行也能使用。需要支持本地 Skill 与 shell 执行的 Agent 客户端，云端沙箱里的 Skill 不能直接访问这台 Mac。Skill 的名称、描述、启用后的说明和命令结果仍占 token。

## 安装

把 App 从 DMG 放到永久本机位置并打开。菜单栏「安装 Skill…」只有「复制 Prompt」和「关闭」；将 Prompt 发给正在使用的 Agent，由它检查当前客户端支持的 Skill 目录，不硬编码某一种客户端配置路径。

Prompt 从当前 App 的 `Bundle.main.bundleURL` 生成绝对路径。CLI 的 `install-skill` 命令把随包说明复制到目标 Skill 目录，并生成 `scripts/edgepeek` 启动脚本。脚本将当前 App 的 CLI 路径作为一个安全引用的 shell 参数保存，支持空格、中文、单引号和 shell 特殊字符。App 移动或重命名后，重新复制 Prompt 安装以更新脚本路径。磁盘映像与 AppTranslocation 临时位置不应成为长期路径。

安装命令示意（目标由当前客户端确定）：

```sh
"/Applications/贴边.app/Contents/MacOS/edgepeek-cli" install-skill /path/to/client/skills/edgepeek
"/path/to/client/skills/edgepeek/scripts/edgepeek" --help
```

安装只写目标 Skill 目录中的 `SKILL.md` 和 `scripts/edgepeek`；Agent 应先检查或备份已有同名 Skill，保留其他文件与配置。安装验证只调用 `--help`，不读取或改写便签。窗口仅复制 Prompt，不自动修改客户端。CLI 或 Skill 资源缺失时禁用复制。

迁移时让 Agent 仅移除当前客户端旧的 `edgepeek` MCP 项，不影响其他服务器。新版 App 不包含 MCP 服务，也无需注册开机 MCP 进程。App 的「登录时启动贴边」继续由 macOS 登录项独立控制。

## CLI 接口

每次运行一个命令，stdout 输出一行 JSON；失败在 stderr 输出 JSON `error`，退出码非零。未知字段、错误类型、非法 UUID 或提醒日期会报错，写入前完成验证。

| 命令 | stdin JSON | 结果 |
| --- | --- | --- |
| `list_notes` | 无需输入 | `count`、`notes` |
| `list_groups` | 无需输入 | `count`、`groups`（首个 hashtag 分组，无 tag 各自成组） |
| `get_note` | `id` | 单条便签 |
| `search_notes` | `query` | `count`、`notes`，匹配正文、标题或标签 |
| `create_note` | `content` 必填，`pinned`、`dueAt` 可选 | 新建便签；trim 为空时报错 |
| `update_note` | `id` 必填，其余三个字段可选 | 修改后的便签，省略字段保持不变 |
| `delete_note` | `id` | `deleted` 原始便签；立即删除，无界面撤销提示 |

`dueAt` 使用带时区的 ISO-8601，接受小数秒；`null` 清除提醒。正文内第一个 hashtag 决定分组和颜色。同组颜色沿用最早便签。新建 `#标签` 本身算非空内容。

```sh
"/Applications/贴边.app/Contents/MacOS/edgepeek-cli" create_note <<'JSON'
{"content":"交稿\n周三前发给编辑。\n#工作","dueAt":"2026-10-28T09:00:00+08:00"}
JSON
```

默认数据文件为 `~/Library/Application Support/EdgePeek/notes.json`。开发/测试设置 `EDGEPEEK_DATA_FILE=/tmp/edgepeek-skill-tests/notes.json`，不要使用真实便签做写入验证。

CLI 写入持有稳定 sidecar 文件锁，并行命令不会互相覆盖新增便签；JSON 仍原子替换。运行中的 App 监听目录并重载。已保存便签同时编辑时最后写入者生效，避免让 Agent 修改正在输入的同一条便签。新建编辑器草稿保持内存内容，外部其他便签更新会合并进来；trim 为空的草稿不写入磁盘，关闭时丢弃，非空草稿自动保存。所有操作仅发生在本机。

## 验证与排查

运行 `swift test` 和 `python3 -m unittest discover -s scripts -p 'test_*.py'`。CLI 集成测试使用隔离数据覆盖七个命令、颜色分组、日期、并行写入不丢便签、无效输入不修改文件、空白拒绝和特殊 App 路径下的真实 Skill 安装/启动。

- Agent 找不到 Skill：检查当前客户端的实际发现目录和重载方式。
- 启动脚本指向旧位置：重新打开移动后的 App，复制新 Prompt 并安装。
- 安装时找不到随包 Skill：重新安装完整 App，不能只复制 CLI 单个文件。
- Agent 改了但 App 没变：检查两边是否使用同一数据文件；同一张新建草稿在关闭前以编辑器内容为准。
