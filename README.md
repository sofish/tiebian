# 贴边 · EdgePeek

> 屏幕边缘只剩一条会呼吸的缝。停上去，所有便签按标签竖着铺开。

![贴边 · EdgePeek](docs/preview.png)

旧版预览；当前分组标签已移到各组顶部。

一个本地运行的 macOS 浮窗便签工具，SwiftUI + AppKit 写成。没有 Dock 图标，住在菜单栏里；现在也可以被 Agent 通过 Skill 读写。

## 现在的样子

**收在边缘**

- 平时只在屏幕边缘留一条很细的缝，没有便签、标签、纸角或胶囊。
- 菜单栏「光条动画」可选流光、呼吸、涟漪，默认流光，选择自动保存。以日出般的暖白光核和琥珀色柔光沿物理屏幕边缘发光，光晕可超出光条厚度与两端；拖它可以换到任意一边，横向/纵向自动切换。
- 菜单栏「光条大小」可连续调节长度：原来的 220pt 为最小，默认 440pt；上限为所在屏幕可用边长的 80%（竖边按高度、横边按宽度）。宽度独立可调，原来的 2.7pt 为最小、默认 5.4pt、最大 16.2pt；亮线贴住屏幕边缘，光核藏在边缘外，只露出柔和的日光弧面；光晕随宽度平缓放大，独立于鼠标命中区域。设置自动保存，换到小屏幕时自动缩短长度。
- 有便签到期时，流光适度加快、光晕增强；**过期数量**会随着流动日光出现（呼吸/涟漪时在中间提示）：没有外框，每隔几秒淡入、跟随日光走两次，再隐去一段时间。
- 缝的窗口在屏幕最上层，其他 App 激活、进入全屏空间或息屏唤醒后仍然在；后台全局鼠标事件、始终有效的 tracking area 和轮询共同检测 hover，不需要先点击激活，展开时不抢焦点。

**展开后**

- 所有便签一次铺开，按第一个 hashtag 分组。
- 单张便签卡片可原生拖出板子，越过边界 24pt 后松手删除，显示 6 秒撤销；板内松手或按 Esc 取消则保留，拖动中板子不自动收起。
- **一个 group 一列**，第一组第一列、第二组第二列；组内便签竖向紧贴，组与组之间的间隔更大。
- 标签放在各自 group 顶部，与便签左侧对齐；每列高度以便签最多的 group 为准，较短的 group 连同顶部标签在列内垂直居中。
- 同 tag 的便签同色、同角度；颜色自动随机，不提供颜色设置。没有 tag 的便签各自成一列。
- 展开的纸张是纯色平铺的：没有渐变、没有描边，也没有顶部胶条；只有轻微纸纹和柔和阴影。
- 每张便签是一个 WYSIWYG 编辑入口，不是 Markdown 源码：
  - 点一下，便签会到屏幕中间变成一张可以写的纸。
  - 新建便签去掉首尾空白后仍为空时只保留为内存草稿，不写入文件；收起或退出时丢弃。只有标签也算内容。
  - 中文全部使用京华老宋，英文、数字和代码使用等宽字体；输入时所见即所得。
  - 右上角有「收起」（透明玻璃按钮）和「…」；到期时间在右下角。
  - 纸顶的胶带是拖动把手：按住只移动整张纸，快速拖动或拖出屏幕都不会删除，松手后回到屏幕可见范围。
  - 「…」里保留置顶和删除；主动删除后底部会出现「撤销」，6 秒内可恢复便签。
- 过期便签在展开时盖一个「过期」印章，一张纸只有一个；同时缝上会出现过期数量。
- 屏幕排不下时先按列分页，页码在板子底部；只有一页时不显示。

**其他**

- 到期时间：底部时钟，支持日期/时间，也支持「1 小时后」「明天 9:00」「下周一」。
- 全局快捷键 `⌘ ⇧ Space` 新建便签；`⌃ ⌥ Space` 显示 / 收起全部便签，无需移动鼠标。快捷键展开后保持显示，不抢其他 App 焦点；再按一次或点光条收起。便签较多时仍按列分页。
- 菜单栏下拉设置分为「配置」和「启动」：光条长宽、光条动画、安装 Skill、便签存放位置、重置贴边位置、登录时启动贴边、管理系统登录项，另有新建、显示 / 收起全部便签、关于和退出。
- 「安装 Skill…」只提供「复制 Prompt」和「关闭」，Prompt 自动使用当前 App 的安装路径，由 Agent 识别客户端并安装本地 Skill。CLI 每次调用即退出，不注册 MCP 或后台服务。登录启动只控制贴边 App，待系统批准时会显示提示。
- 本地 JSON 持久化，支持多屏、全屏空间、窗口置顶；不需要辅助功能权限。
- 数据目录里的 `notes.json` 被外部修改时，运行中的贴边会自动刷新。

## 构建和运行

要求：macOS 14+，Xcode / Swift 6 工具链。

```bash
# 构建、打包到 dist/贴边.app；同时构建本地 CLI 并打包 Skill
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

开发构建默认使用 ad-hoc 签名。GitHub Release 的 DMG / ZIP 使用 Developer ID 签名和 Apple 公证，支持 Apple Silicon 与 Intel Mac；解压或挂载后把 App 拖到 Applications，再打开。打包与验证流程见 [`docs/release.md`](docs/release.md)。

## Agent / Skill

App 随包附带 `Contents/MacOS/edgepeek-cli` 和 `Contents/Resources/Skills/edgepeek/SKILL.md`。
菜单栏「安装 Skill…」→「复制 Prompt」，交给支持本地 Skill 和 shell 的 Agent 安装；它会按当前客户端的实际路径安装 Skill 与指向 App 的启动脚本，并移除该客户端已有的 `edgepeek` MCP 配置项，保留其他配置。

Skill 按需读取说明，通过本地 CLI 读写同一份 `notes.json`，无需常驻服务、端口或网络；App 不在前台甚至未运行也可使用。Skill 的元数据、启用后的说明和调用结果仍占 token，不声称零 token。移动或重命名 App 后重新复制 Prompt 安装即可。

详细安装、七个命令、提醒与数据同步约束见 [Skill 文档](docs/skill.md)。

## 数据放在哪里

- 便签：`~/Library/Application Support/EdgePeek/notes.json`
- 贴边位置：`UserDefaults` 里的 `com.sofish.edgepeek` → `EdgePeek.anchor.v1`
- 光条长度：同一 `UserDefaults` 下的 `EdgePeek.seamLength.v1`；没有设置时使用 440pt。
- 光条动画：`EdgePeek.seamAnimation.v1`；默认 `flow`，另有 `breathe` / `ripple`。
- 光条宽度：`EdgePeek.seamWidth.v1`；没有设置时使用 5.4pt。
- CLI：`dist/贴边.app/Contents/MacOS/edgepeek-cli`
- Skill：`dist/贴边.app/Contents/Resources/Skills/edgepeek/SKILL.md`

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

- **缝**：原生 Core Animation 在合成器中连续运行，避免定时触发整棵 SwiftUI 重绘；渐细底光上叠加暖白光核、金色内晕与琥珀色外晕。流光的日光点从左向右移动（竖边从上向下），呼吸像经典待机灯原地缓缓明暗，涟漪由两圈相差半周期的柔光波纹向外扩散；独立的鼠标穿透子面板容纳溢出光晕，点击、hover 和拖动仍使用原来的窄光条。过期数量与日光共用相位，并按 2 次走过 / 2 次隐藏的周期淡入淡出。
- **列布局**：以便签最多的 group 的高度为公共列高；每组顶部预留标签和间距，组内步长优先 `cardHeight + gap`，空间不足时按比例压缩，短 group 连同标签在列内垂直居中。
- **分组**：只取第一个 hashtag；没有 hashtag 的便签每张单独成组，所以不会被强行合并到「随手」。
- **颜色**：新建时随机选一个未占用的柔和纸色；同 tag 取最老一张的颜色并同步，不提供颜色 UI。
- **纸张**：SwiftUI 纯色纸 + 细纸纹 + 多层柔和阴影；没有渐变和描边。编辑纸顶部保留一条可拖动的胶带。
- **编辑器**：`NSTextView` 作为纸张本体，中文/英文按字符 run 混排；没有 Markdown 源码视图。旧 Markdown 便签在打开时会被转换成可读的纯文本（项目符号、勾选框保留为字形）。
- **手势**：顶部胶带使用独立 AppKit view 处理原生鼠标事件，按屏幕坐标移动面板，松手后约束到屏幕可见范围；不拦截其他控件的点击。删除只从「…」触发，Undo toast 恢复。
- **Agent**：独立的 `EdgePeekCLI` 可执行文件读取/写入同一个 JSON；App 用 `DispatchSource` 监听目录变化并重载。
- **置顶与 hover**：缝、便签板和编辑器使用高 window level；全局鼠标移动监听在其他 App 前台时也驱动检测，tracking area、100ms 轮询和防止 App Nap 的 activity 兜底。便签板使用不激活的面板。

## 目录

```
Sources/
  EdgePeekCore/          数据模型、tag 解析、分组、颜色同步、持久化、文本转换、边缘几何
  EdgePeek/
    Views/               缝、group 列板、纸张卡片、WYSIWYG 编辑器、撤销
    Windows/             AppKit 面板、贴边控制器、编辑器控制器、文件监听
    UI/                  主题、布局、混排字体、纸张与玻璃控件
    Support/             全局快捷键、菜单栏图标、登录启动、字体注册
  EdgePeekCLI/           单次调用的本地 JSON CLI 与文件服务
Tests/EdgePeekCoreTests/ 数据、分组、颜色、到期、文本、几何与删除撤销测试
Tests/EdgePeekTests/     group 顶部标签布局、分页、原生拖动与控件命中范围测试
scripts/                 构建 .app + CLI + Skill、生成 .icns
Resources/               Info.plist、AppIcon.icns、京华老宋字体与授权
docs/                    预览图、Skill 安装说明、交互回归验收、macOS 发布流程
```

## 技术栈

- SwiftUI 负责缝的动画、纸张排版、便签板和 WYSIWYG 纸张；AppKit 负责无边框透明面板、置顶、多屏吸附、鼠标手势和文件监听。
- 没有第三方运行时依赖；字体和图标随包分发。
- 全局快捷键用 Carbon `RegisterEventHotKey`，登录启动用 `SMAppService.mainApp`。
- Skill 通过 stdin JSON 调用 Swift CLI，直接复用 `EdgePeekCore` 的数据模型。
