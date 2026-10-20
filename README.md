# 贴边 · EdgePeek

> 屏幕边缘只剩一条会呼吸的缝。停上去，所有便签按标签竖着铺开。

![贴边 · EdgePeek](docs/preview.png)

一个本地运行的 macOS 浮窗便签工具，SwiftUI + AppKit 写成。没有 Dock 图标，住在菜单栏里；现在也可以被 Agent 通过 MCP 读写。

## 现在的样子

**收在边缘**

- 平时只在屏幕边缘留一条很细的缝，没有便签、标签、纸角或胶囊。
- 缝一直有暖色流光；拖它可以换到任意一边，横向/纵向自动切换。
- 有便签到期时，流光更快、更亮；**过期数量**会随着流动光点出现：没有外框，每隔几秒淡入、跟随光点走两次，再隐去一段时间。
- 缝的窗口在屏幕最上层，其他 App 激活、进入全屏空间或息屏唤醒后仍然在；hover 不依赖点击激活。

**展开后**

- 所有便签一次铺开，按第一个 hashtag 分组。
- **一个 group 一列**，第一组第一列、第二组第二列；组内便签竖向紧贴，组与组之间的间隔更大。
- 标签在每列左侧、垂直居中；每列高度以标签最多的 group 为准，较短的 group 在列内垂直居中。
- 同 tag 的便签同色、同角度；颜色自动随机，不提供颜色设置。没有 tag 的便签各自成一列。
- 展开的纸张是纯色平铺的：没有渐变、没有描边，也没有顶部胶条；只有轻微纸纹和柔和阴影。
- 每张便签是一个 WYSIWYG 编辑入口，不是 Markdown 源码：
  - 点一下，便签会到屏幕中间变成一张可以写的纸。
  - 中文全部使用京华老宋，英文、数字和代码使用等宽字体；输入时所见即所得。
  - 右上角有「收起」（透明玻璃按钮）和「…」；到期时间在右下角。
  - 纸顶的胶带是拖动把手：按住拖动整张纸，快速甩出去删除；删除后底部会出现「撤销」。
- 过期便签在展开时盖一个「过期」印章，一张纸只有一个；同时缝上会出现过期数量。
- 屏幕排不下时先按列分页，页码在板子底部；只有一页时不显示。

**其他**

- 到期时间：底部时钟，支持日期/时间，也支持「1 小时后」「明天 9:00」「下周一」。
- 全局快捷键 `⌘ ⇧ Space` 新建便签。
- 菜单栏：新建便签、便签位置、Agent / MCP、登录启动、重置贴边位置、关于、退出。
- 本地 JSON 持久化，支持多屏、全屏空间、窗口置顶；不需要辅助功能权限。
- 数据目录里的 `notes.json` 被外部修改时，运行中的贴边会自动刷新。

## 构建和运行

要求：macOS 14+，Xcode / Swift 6 工具链。

```bash
# 构建、打包到 dist/贴边.app；同时构建 MCP helper
./scripts/build-app.sh release

open "dist/贴边.app"
```

测试：

```bash
swift test
```

重新生成图标：

```bash
./scripts/make-icon.sh
```

App 是本地 ad-hoc 签名，没有公证。第一次打开如果被 Gatekeeper 拦，右键「打开」。

## Agent / MCP

随 App 一起安装了一个本地 stdio MCP 服务：

```text
dist/贴边.app/Contents/MacOS/edgepeek-mcp
```

它和 App 使用同一份 `notes.json`；Agent 修改后，正在运行的贴边会自动刷新。它是本地进程，不开端口，也不上传任何数据。

菜单栏「Agent / MCP…」可以直接复制配置。项目里也已经有一份配置好的 `opencode.json`（OpenCode V2 使用 `mcp.servers`）：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "edgepeek": {
        "type": "local",
        "command": ["/Users/sofish/Codes/tiebian/dist/贴边.app/Contents/MacOS/edgepeek-mcp"]
      }
    }
  }
}
```

也可以用命令添加：

```bash
opencode mcp add edgepeek -- "$(pwd)/dist/贴边.app/Contents/MacOS/edgepeek-mcp"
```

Claude Code：

```bash
claude mcp add edgepeek -- "$(pwd)/dist/贴边.app/Contents/MacOS/edgepeek-mcp"
```

工具：

| 工具 | 作用 |
| --- | --- |
| `list_notes` | 全部便签及正文、标题、标签、颜色、置顶、创建/更新/到期时间、是否过期 |
| `list_groups` | 按第一个 hashtag 分组后的列表；无 tag 便签各自成组 |
| `get_note` | 按 UUID 读取一张 |
| `create_note` | 新建；hashtag 决定分组，颜色自动分配 |
| `update_note` | 改正文、置顶、到期时间；`dueAt: null` 清除提醒 |
| `delete_note` | 删除 |
| `search_notes` | 搜索正文、标题、标签 |

详细配置、示例提示和排查见 [`docs/mcp.md`](docs/mcp.md)。

## 数据放在哪里

- 便签：`~/Library/Application Support/EdgePeek/notes.json`
- 贴边位置：`UserDefaults` 里的 `com.sofish.edgepeek` → `EdgePeek.anchor.v1`
- MCP helper：`dist/贴边.app/Contents/MacOS/edgepeek-mcp`

JSON 自动保存；损坏的文件会先备份，不会直接覆盖。

## 字体

- 中文：**京華老宋体 / KingHwaOldSong 3.0**，由特里王制作。字体随 App 一起分发，免费商用、可嵌入软件，但不可单独转售；授权原文在 [`Resources/KingHwaOldSong-LICENSE.txt`](Resources/KingHwaOldSong-LICENSE.txt)。
- 英文/数字：系统等宽字体（SF Mono）。

## 开发用启动参数

这些只在开发时用，正常启动不需要：

| 环境变量 | 作用 |
| --- | --- |
| `EDGEPEEK_DATA_FILE` | 指定独立的 JSON 数据文件，避免测试时碰真实数据 |
| `EDGEPEEK_POSITION` | `left` / `right` / `top` / `bottom`，启动时把缝放到指定边 |
| `EDGEPEEK_DEMO=1` | 启动后直接铺开便签板 |
| `EDGEPEEK_NOTE_INDEX` | demo / editor 使用第几张便签 |
| `EDGEPEEK_EDITOR=1` | 启动后打开某张便签的编辑器 |
| `EDGEPEEK_DUE_DEMO=1` | 把第一张便签设置为已到期，方便看缝的提醒数量和印章 |
| `EDGEPEEK_DUE_PICKER=1` | 打开编辑器时顺手展开日期选择器 |
| `EDGEPEEK_SIMULATE_HOVER=1` | 用代码模拟鼠标停在缝上（不移动真实鼠标） |
| `EDGEPEEK_HOLD=1` | 关闭自动 hover 检测，方便截图 |
| `EDGEPEEK_DEBUG=1` | 输出调试日志 |

例如：

```bash
EDGEPEEK_DATA_FILE=/tmp/edgepeek-demo.json \
EDGEPEEK_POSITION=left \
EDGEPEEK_DEMO=1 \
EDGEPEEK_HOLD=1 \
"dist/贴边.app/Contents/MacOS/EdgePeek"
```

## 一些实现细节

- **缝**：`TimelineView` 驱动的流动光；过期数量与光点共用相位，并按 2 次走过 / 2 次隐藏的周期淡入淡出。
- **列布局**：以标签最多的 group 的高度为公共列高；组内步长优先 `cardHeight + gap`，空间不足时按比例压缩，短 group 在列内垂直居中。
- **分组**：只取第一个 hashtag；没有 hashtag 的便签每张单独成组，所以不会被强行合并到「随手」。
- **颜色**：新建时随机选一个未占用的柔和纸色；同 tag 取最老一张的颜色并同步，不提供颜色 UI。
- **纸张**：SwiftUI 纯色纸 + 细纸纹 + 多层柔和阴影；没有渐变和描边。编辑纸顶部保留一条可拖动的胶带。
- **编辑器**：`NSTextView` 作为纸张本体，中文/英文按字符 run 混排；没有 Markdown 源码视图。旧 Markdown 便签在打开时会被转换成可读的纯文本（项目符号、勾选框保留为字形）。
- **手势**：顶部胶带区域由 AppKit 本地事件监听驱动，移动面板；末尾速度峰值 + 出屏判断触发删除，Undo toast 恢复。
- **Agent**：独立的 `EdgePeekMCP` 可执行文件读取/写入同一个 JSON；App 用 `DispatchSource` 监听目录变化并重载。
- **置顶**：缝、便签板和编辑器使用高 window level；鼠标 tracking area + 防止 App Nap 的 activity 保证首次 hover 也可靠。

## 目录

```
Sources/
  EdgePeekCore/          数据模型、tag 解析、分组、颜色同步、持久化、文本转换、边缘几何
  EdgePeek/
    Views/               缝、group 列板、纸张卡片、WYSIWYG 编辑器、撤销
    Windows/             AppKit 面板、贴边控制器、编辑器控制器、文件监听
    UI/                  主题、布局、混排字体、纸张与玻璃控件
    Support/             全局快捷键、菜单栏图标、登录启动、字体注册
  EdgePeekMCP/           本地 stdio MCP server 与文件服务
Tests/EdgePeekCoreTests/ 数据、分组、颜色、到期、文本与几何测试
scripts/                 构建 .app + MCP helper、生成 .icns
Resources/               Info.plist、AppIcon.icns、京华老宋字体与授权
docs/                    预览图、MCP 配置说明
```

## 技术栈

- SwiftUI 负责缝的动画、纸张排版、便签板和 WYSIWYG 纸张；AppKit 负责无边框透明面板、置顶、多屏吸附、鼠标手势和文件监听。
- 没有第三方运行时依赖；字体和图标随包分发。
- 全局快捷键用 Carbon `RegisterEventHotKey`，登录启动用 `SMAppService.mainApp`。
- MCP 是手写的 stdio JSON-RPC server，直接复用 `EdgePeekCore` 的数据模型。
