# 用 Agent 操作贴边

贴边附带一个本地 MCP（Model Context Protocol）服务：

```text
dist/贴边.app/Contents/MacOS/edgepeek-mcp
```

它是一个 **stdio MCP server**。Agent 客户端负责启动它；它不需要单独开端口，也不访问网络。每次工具调用都直接读写贴边使用的同一份 `notes.json`。贴边 App 正在运行时会监听这个文件，Agent 修改后界面会自动刷新；App 没开时，下次启动会读到新内容。

## 打开方式

1. 构建 App：

   ```bash
   ./scripts/build-app.sh release
   ```

2. 找到 helper：

   ```bash
   "$(pwd)/dist/贴边.app/Contents/MacOS/edgepeek-mcp"
   ```

3. 把它配置到你的 Agent 客户端。

> 菜单栏「本地 MCP…」只提供「复制 Prompt」和「关闭」。复制后发给正在使用的 Agent，让它识别当前客户端、保留已有服务器并完成配置；不需要先选择 OpenCode / Claude 等客户端。

Prompt 使用当前运行 App 的实际安装位置生成绝对路径，不含开发者账户路径。比如默认安装到 `/Applications/贴边.app` 时，helper 位于 `/Applications/贴边.app/Contents/MacOS/edgepeek-mcp`；放在其他本机文件夹或重命名后，重新打开 App 并复制即可。移动或重命名 App 后，旧客户端配置不会自行更新，需要再复制一次 Prompt。应先把 App 从 DMG 放到永久本机位置；Prompt 会要求 Agent 检查磁盘映像和 AppTranslocation，避免保存临时路径。

helper 缺失时窗口说明原因并禁用复制。Prompt 只要求通过 initialize / tools/list 验证，不读写测试便签，也不安装额外后台服务。

## 启动与设置

- 菜单栏「配置」区集中管理光条大小、本地 MCP、便签存放位置和贴边位置重置。
- 「启动」区的「登录时启动贴边」通过 macOS 登录项控制 App 自启动；勾选代表已启用，半选并显示「待系统批准」表示还需在系统设置批准。待批准时仍可取消注册。
- 「管理系统登录项…」直接打开 macOS 的登录项设置。
- MCP 保持 stdio：客户端启动并持有它的输入/输出管道，连接时自动启动，不单独注册开机常驻进程。贴边 App 未运行也能使用 MCP；App 自启动和 MCP 按需启动是两个独立的生命周期。
- 配置菜单只生成并复制文本，不会自动修改客户端文件或安装后台服务。

### OpenCode

把这段放进 `opencode.json`（项目级或全局配置均可），重启 OpenCode：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "edgepeek": {
        "type": "local",
        "command": ["/Applications/贴边.app/Contents/MacOS/edgepeek-mcp"]
      }
    }
  }
}
```

### Claude Code

```bash
claude mcp add edgepeek -- "/Applications/贴边.app/Contents/MacOS/edgepeek-mcp"
```

OpenCode 也可以直接用命令添加，避免手改 JSON：

```bash
opencode mcp add edgepeek -- "$(pwd)/dist/贴边.app/Contents/MacOS/edgepeek-mcp"
```

### Claude Desktop / Cursor

`claude_desktop_config.json` 或 `.cursor/mcp.json`：

```json
{
  "mcpServers": {
    "edgepeek": {
      "command": "/Applications/贴边.app/Contents/MacOS/edgepeek-mcp"
    }
  }
}
```

修改客户端配置后需要重启或重新加载 MCP 服务。

## 工具有哪些

| 工具 | 作用 |
| --- | --- |
| `list_notes` | 读取全部便签：正文、标题、标签、颜色、置顶、创建/更新时间、到期时间、是否过期 |
| `list_groups` | 按第一个 hashtag 分组后的列表；没有 tag 的便签各自成组 |
| `get_note` | 按 UUID 读取一张便签 |
| `create_note` | 新建便签；`content` 里的 hashtag 会决定分组，颜色自动分配 |
| `update_note` | 修改正文、置顶或到期时间；`dueAt: null` 表示清除提醒 |
| `delete_note` | 删除便签 |
| `search_notes` | 搜索正文、标题和标签 |

`create_note` / `update_note` 的 `dueAt` 使用 ISO-8601，例如：

```json
{
  "content": "交稿\n下周三前给编辑。\n#工作",
  "dueAt": "2026-10-28T09:00:00Z",
  "pinned": true
}
```

## Agent 可以怎么用

```text
列出所有已经过期的便签，按到期时间排序。
把「下周的提案」那条便签的截止时间改到明天 9 点。
新建一条以 #读书 开头的便签，记下《枕草子》的读书笔记。
把所有 #工作 里包含“邮件”的便签找出来。
```

## 数据与同步

- 默认数据文件：`~/Library/Application Support/EdgePeek/notes.json`
- 开发/测试时可以给 MCP 进程设置 `EDGEPEEK_DATA_FILE`，让它使用另一份文件：

  ```json
  {
    "mcpServers": {
      "edgepeek-dev": {
        "command": "/path/to/edgepeek-mcp",
        "env": {
          "EDGEPEEK_DATA_FILE": "/tmp/edgepeek-dev.json"
        }
      }
    }
  }
  ```

- MCP 工具会以原子方式写 JSON。贴边 App 监听所在目录，外部写入后自动重新载入，不需要刷新或重启。
- 如果 App 正在编辑某张便签，而 Agent 同时改了同一张，以最后一次写入为准；建议不要在输入过程中让 Agent 修改同一张便签。
- 所有修改都只发生在本机，不会上传到任何地方。

## 排查

- **客户端看不到工具**：确认 helper 路径存在、可执行；重启 MCP 客户端。
- **Agent 改了但 App 没变**：确认 App 和 MCP 指向同一个数据文件；App 需要保持运行才能实时刷新。
- **中文变成乱码**：MCP 使用 UTF-8 和标准 JSON；客户端应能直接读取。
- **想自己试协议**：它遵循 stdio JSON-RPC，一行一条消息：

  ```bash
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"shell","version":"1"}}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    | "dist/贴边.app/Contents/MacOS/edgepeek-mcp"
  ```
