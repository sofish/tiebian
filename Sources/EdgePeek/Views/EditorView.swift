import EdgePeekCore
import SwiftUI

struct EditorView: View {
    @ObservedObject var store: NoteStore
    let noteID: UUID
    let isNew: Bool
    let onClose: () -> Void
    let onDelete: () -> Void
    let onDragEnded: () -> Void

    @State private var text: String
    @State private var showActions = false
    @State private var showDuePicker = false
    @State private var dueDraft: Date
    @State private var actionsHovered = false
    @State private var closeHovered = false
    @State private var dueHovered = false

    init(
        store: NoteStore,
        note: StickyNote,
        isNew: Bool,
        onClose: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onDragEnded: @escaping () -> Void
    ) {
        self.store = store
        self.noteID = note.id
        self.isNew = isNew
        self.onClose = onClose
        self.onDelete = onDelete
        self.onDragEnded = onDragEnded
        _text = State(initialValue: NoteText.plainText(from: note.content))
        _dueDraft = State(
            initialValue: note.dueAt ?? Date().addingTimeInterval(60 * 60)
        )
    }

    private var note: StickyNote? {
        store.note(with: noteID)
    }

    private var paperColor: NoteColor {
        note?.color ?? .cream
    }

    private var dueAt: Date? {
        note?.dueAt
    }

    private var dueIsOverdue: Bool {
        guard let dueAt else { return false }
        return dueAt <= Date()
    }

    private var dueLabel: String {
        guard let dueAt else { return "设个时间" }
        return DateText.dueShort(dueAt)
    }

    var body: some View {
        ZStack(alignment: .top) {
            radialShadow
                .frame(width: 550, height: 620)
                .padding(.top, 20)
                .allowsHitTesting(false)

            paper
                .frame(width: Layout.paperSize.width, height: Layout.paperSize.height)
                .padding(.top, 80)

            tape
                .offset(y: 60)
        }
        .frame(width: Layout.editorSize.width, height: Layout.editorSize.height)
        .onExitCommand {
            onClose()
        }
        .onChange(of: text) { _, value in
            guard value != note?.content else { return }
            store.updateContent(id: noteID, content: value)
        }
        .onChange(of: showDuePicker) { _, presented in
            if presented {
                dueDraft = dueAt ?? Date().addingTimeInterval(60 * 60)
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["EDGEPEEK_DUE_PICKER"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showDuePicker = true
                }
            }
        }
    }

    // MARK: - The paper

    private var paper: some View {
        ZStack(alignment: .topLeading) {
            PaperBackground(color: paperColor, cornerRadius: 4)
            PaperTexture(opacity: 0.032)

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    PaperTextEditor(
                        text: $text,
                        fontSize: 18,
                        textColor: NSColor(Theme.ink),
                        accentColor: NSColor(Theme.accentDeep),
                        autoFocus: true
                    )
                    .padding(.horizontal, 27)
                    .padding(.top, 3)
                    .padding(.bottom, 2)

                    if text.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            MixedText(
                                "写点什么…",
                                size: 18,
                                color: Theme.inkFaint.opacity(0.62)
                            )
                            MixedText(
                                "用 #标签 把同类纸片放在一起",
                                size: 9.8,
                                color: Theme.inkFaint.opacity(0.5)
                            )
                        }
                        .padding(.leading, 30)
                        .padding(.top, 5)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 48)
                .padding(.bottom, 56)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.inkFaint.opacity(0.5))
                        .frame(width: 3, height: 3)
                    MixedText(
                        "\(text.count) 字 · 自动保存",
                        size: 8.2,
                        color: Theme.inkFaint
                    )
                    Spacer(minLength: 4)
                    dueButton
                }
                .padding(.horizontal, 21)
                .padding(.bottom, 14)
            }

            if note?.isPinned == true {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep.opacity(0.75))
                    .padding(.leading, 17)
                    .padding(.top, 16)
            }

            HStack(spacing: 5) {
                Button(action: onClose) {
                    MixedText("收起", size: 10.2, color: Theme.ink.opacity(0.86))
                        .padding(.horizontal, 11)
                        .frame(height: 27)
                        .background(
                            ZStack {
                                LiquidGlassBackground(shape: Capsule())
                                Capsule()
                                    .fill(
                                        Color.white.opacity(closeHovered ? 0.11 : 0)
                                    )
                            }
                        )
                        .contentShape(Capsule())
                        .scaleEffect(closeHovered ? 1.015 : 1)
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
                .animation(Theme.quickSpring, value: closeHovered)
                .help("收起便签（Esc）")

                Button {
                    withAnimation(Theme.quickSpring) {
                        showActions.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .frame(width: 29, height: 29)
                        .background(
                            Circle()
                                .fill(
                                    actionsHovered || showActions
                                        ? Theme.ink.opacity(0.065)
                                        : Color.clear
                                )
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { actionsHovered = $0 }
                .animation(Theme.quickSpring, value: actionsHovered)
                .help("更多操作")
                .popover(isPresented: $showActions, arrowEdge: .top) {
                    actionMenu
                        .preferredColorScheme(.light)
                }
            }
            .padding(.trailing, 12)
            .padding(.top, 12)
            .frame(
                width: Layout.paperSize.width,
                height: Layout.paperSize.height,
                alignment: .topTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        // Four stacked blurs give the paper a gradual, radial falloff. A
        // single large window shadow gets clipped into the rectangular block
        // this replaces.
        .shadow(color: Theme.shadow.opacity(0.06), radius: 2, y: 1)
        .shadow(color: Theme.shadow.opacity(0.08), radius: 9, y: 5)
        .shadow(color: Theme.shadow.opacity(0.07), radius: 24, y: 12)
        .shadow(color: Theme.shadow.opacity(0.05), radius: 46, y: 24)
    }

    private var radialShadow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Theme.shadow.opacity(0.15),
                        Theme.shadow.opacity(0.065),
                        Theme.shadow.opacity(0)
                    ],
                    center: .center,
                    startRadius: 24,
                    endRadius: 305
                )
            )
            .blur(radius: 20)
    }

    private var tape: some View {
        ZStack {
            TapeShape()
                .fill(Theme.tape.opacity(0.48))
                .frame(width: 106, height: 23)
                .rotationEffect(.degrees(-4.5))
                .blendMode(.multiply)
                .allowsHitTesting(false)
            WindowDragHandle(onDragEnded: onDragEnded)
        }
        .frame(width: 184, height: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Due date

    private var dueButton: some View {
        Button {
            dueDraft = dueAt ?? Date().addingTimeInterval(60 * 60)
            showDuePicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 7.5, weight: .medium))
                MixedText(
                    dueLabel,
                    size: 8.2,
                    weight: dueAt == nil ? .regular : .medium,
                    color: dueAt == nil
                        ? Theme.inkFaint
                        : (dueIsOverdue ? Theme.accentDeep : Theme.inkSoft)
                )
                .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(
                        dueHovered
                            ? Theme.ink.opacity(0.06)
                            : (dueIsOverdue
                                ? Theme.accent.opacity(0.08)
                                : Color.clear)
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { dueHovered = $0 }
        .help(dueAt.map { "提醒：\(DateText.dueFull($0))" } ?? "设置到期提醒")
        .popover(isPresented: $showDuePicker, arrowEdge: .bottom) {
            duePicker
                .preferredColorScheme(.light)
        }
    }

    private var duePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                MixedText("提醒时间", size: 18, color: Theme.ink)
                Spacer()
                if dueAt != nil {
                    Button {
                        store.setDueDate(id: noteID, dueAt: nil)
                        showDuePicker = false
                    } label: {
                        MixedText("清除", size: 9.5, color: Theme.accentDeep)
                    }
                    .buttonStyle(.plain)
                }
            }

            DatePicker(
                "",
                selection: $dueDraft,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.field)
            .labelsHidden()
            .tint(Theme.accent)

            HStack(spacing: 6) {
                quickDueButton("1 小时后") {
                    dueDraft = Date().addingTimeInterval(3600)
                }
                quickDueButton("明天 9:00") {
                    dueDraft = Self.tomorrowAtNine()
                }
                quickDueButton("下周一") {
                    dueDraft = Self.nextMondayAtNine()
                }
            }

            HStack {
                Spacer()
                Button {
                    showDuePicker = false
                } label: {
                    MixedText("取消", size: 9.5, color: Theme.inkSoft)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)

                Button {
                    store.setDueDate(id: noteID, dueAt: dueDraft)
                    showDuePicker = false
                } label: {
                    MixedText("设好", size: 9.5, weight: .medium, color: .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.ink))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(paperColor.paperTop)
    }

    private func quickDueButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MixedText(title, size: 7.8, color: Theme.inkSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Theme.ink.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hidden actions

    private var actionMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            actionRow(
                icon: note?.isPinned == true ? "pin.slash" : "pin",
                title: note?.isPinned == true ? "取消置顶" : "置顶"
            ) {
                store.togglePin(id: noteID)
                showActions = false
            }
            actionRow(icon: "trash", title: "删除便签", destructive: true) {
                showActions = false
                onDelete()
            }
        }
        .padding(6)
        .frame(width: 166)
        .background(paperColor.paperTop)
    }

    private func actionRow(
        icon: String,
        title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 15)
                MixedText(
                    title,
                    size: 10.5,
                    color: destructive ? Theme.accentDeep : Theme.ink
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(EditorActionButtonStyle())
    }

    private static func tomorrowAtNine() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
            ?? tomorrow
    }

    private static func nextMondayAtNine() -> Date {
        let calendar = Calendar.current
        var date = Date()
        repeat {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } while calendar.component(.weekday, from: date) != 2
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
            ?? date
    }
}

private struct EditorActionButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        hovering || configuration.isPressed
                            ? Theme.ink.opacity(0.055)
                            : Color.clear
                    )
            )
            .onHover { hovering = $0 }
    }
}

struct TapeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notch = min(3.2, rect.height * 0.18)
        path.move(to: CGPoint(x: 0, y: 1.4))
        path.addLine(to: CGPoint(x: rect.width, y: 0.2))
        path.addLine(to: CGPoint(x: rect.width - notch, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - 0.4))
        path.addLine(to: CGPoint(x: 0, y: rect.height - 1.6))
        path.addLine(to: CGPoint(x: notch, y: rect.height * 0.48))
        path.closeSubpath()
        return path
    }
}
