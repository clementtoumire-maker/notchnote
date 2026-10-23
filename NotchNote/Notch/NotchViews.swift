import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shape & material

/// Flat top (so it fuses with the hardware notch), rounded bottom corners. On notchless displays it is a
/// fully rounded "Dynamic Island" pill.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var hasNotch: Bool

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        if !hasNotch {
            return RoundedRectangle(cornerRadius: min(bottomRadius, rect.height / 2), style: .continuous).path(in: rect)
        }
        let r = max(0, min(bottomRadius, rect.width / 2, rect.height))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        p.closeSubpath()
        return p
    }
}

/// Black on notch displays (it must be indistinguishable from the hardware notch).
/// Translucent glass on displays without a notch.
struct NotchBackground: View {
    let hasNotch: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if hasNotch || reduceTransparency {
            Color.black
        } else {
            GlassSurface()
        }
    }
}

/// Liquid Glass-inspired surface built from public, backwards-compatible pieces: a blurred material,
/// a dark tint for legibility, a soft top highlight and a specular edge (see GlassEdge).
/// (It deliberately does not call the macOS 26 `glassEffect` API so the project builds on any Xcode
/// that can target macOS 15.)
struct GlassSurface: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Color.black.opacity(0.38))       // keep light text legible on bright wallpapers
            LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.02), Color.white.opacity(0.08)],
                           startPoint: .top, endPoint: .bottom)
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct GlassEdge: ViewModifier {
    let hasNotch: Bool
    let shape: NotchShape
    @ViewBuilder
    func body(content: Content) -> some View {
        if hasNotch {
            content
        } else {
            content.overlay(
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
    }
}

extension NotchShape {
    func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: CGFloat) -> some View {
        self.stroke(style, lineWidth: lineWidth)
    }
}

// MARK: - Collapsed pill (lives in the hot-zone window)

struct CollapsedPillView: View {
    @ObservedObject var state: PanelState
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = TaskStore.shared

    var body: some View {
        let size = state.geometry.collapsedSize(settings)
        let shape = NotchShape(bottomRadius: NotchGeometry.hardwareCornerRadius, hasNotch: state.geometry.hasNotch)
        let unchecked = store.tasks.reduce(0) { $0 + $1.uncheckedCount }
        ZStack(alignment: .top) {
            NotchBackground(hasNotch: state.geometry.hasNotch)
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .modifier(GlassEdge(hasNotch: state.geometry.hasNotch, shape: shape))
                .overlay {
                    if !state.geometry.hasNotch {
                        HStack(spacing: 5) {
                            Image(systemName: "note.text").font(.system(size: 11, weight: .medium))
                            if unchecked > 0 {
                                Text("\(unchecked)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                            }
                        }
                        .foregroundStyle(.white.opacity(0.85))
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(state.isOpen ? 0 : 1)
    }
}

// MARK: - Expanded panel

struct NotchPanelView: View {
    @ObservedObject var state: PanelState
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = TaskStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editingTitle = false
    @State private var dropTargeted = false
    @State private var resizeStart: CGSize?
    @FocusState private var titleFocused: Bool

    private var geo: NotchGeometry { state.geometry }

    var body: some View {
        let full = geo.expandedSize(settings)
        let collapsed = geo.collapsedSize(settings)
        let size = state.isOpen ? full : collapsed
        let shape = NotchShape(bottomRadius: state.isOpen ? 26 : (geo.hasNotch ? NotchGeometry.hardwareCornerRadius : 15), hasNotch: geo.hasNotch)
        let openAnim: Animation = reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.70)
        let closeAnim: Animation = reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.88)

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchBackground(hasNotch: geo.hasNotch)
                content
                    .frame(width: full.width, height: full.height, alignment: .top)
                    .opacity(state.isOpen ? 1 : 0)
                    .allowsHitTesting(state.isOpen)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .modifier(GlassEdge(hasNotch: geo.hasNotch, shape: shape))
            .overlay(dropOverlay(shape: shape, size: size))
        }
        .frame(width: full.width, height: full.height, alignment: .top)
        .animation(state.isOpen ? openAnim : closeAnim, value: state.isOpen)
        .foregroundStyle(settings.textColor)
        .tint(settings.textColor)
        .onChange(of: state.isOpen) { _, open in
            if !open { editingTitle = false; titleFocused = false }     // title editing ends with the panel
        }
        .onDrop(of: [UTType.plainText], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 8) {
            header
            Group {
                switch state.tab {
                case .notes: notesPane
                case .cards: CardsView()
                case .today: TodayView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.top, geo.hasNotch ? geo.hardwareNotch.height + 4 : 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(store.tasks) { t in
                    Button(t.title.isEmpty ? "Untitled" : t.title) { store.selectedID = t.id }
                }
                Divider()
                Button("New Task") { store.createTask() }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help("Switch task")

            if editingTitle {
                TextField("Title", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .focused($titleFocused)
                    .onSubmit { editingTitle = false }
            } else {
                Text((store.selectedTask?.title).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .onTapGesture {
                        editingTitle = true
                        DispatchQueue.main.async { titleFocused = true }
                    }
                    .help("Click to rename")
            }

            if let t = store.selectedTask, t.checkedCount + t.uncheckedCount > 0 {
                Text("\(t.checkedCount)/\(t.checkedCount + t.uncheckedCount)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(t.uncheckedCount == 0 ? Color.green.opacity(0.28) : Color.white.opacity(0.12)))
            }

            Spacer(minLength: 4)

            Picker("", selection: $state.tab) {
                Text("Notes").tag(PanelTab.notes)
                Text("Today").tag(PanelTab.today)
                Text("Cards").tag(PanelTab.cards)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)

            iconButton(isFav ? "star.fill" : "star", help: "Favorite (\u{2318}\u{21E7}S)") {
                if let id = store.selectedID { store.toggleFavorite(id) }
            }
            iconButton("plus", help: "New task") { store.createTask(); state.tab = .notes }
            iconButton("macwindow", help: "Open task window") { WindowManager.shared.showTasks() }
            iconButton(state.pinned ? "pin.fill" : "pin", help: "Keep open") { state.pinned.toggle() }
            iconButton("gearshape", help: "Settings") { WindowManager.shared.showSettings() }
        }
        .font(.system(size: 13))
    }

    private var isFav: Bool { store.selectedTask?.isFavorite ?? false }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(0.85)
        .help(help)
    }

    @ViewBuilder private var notesPane: some View {
        if let t = store.selectedTask {
            VStack(spacing: 6) {
                MarkdownEditor(documentID: t.id,
                               markdown: bodyBinding,
                               textColor: settings.nsTextColor,
                               onActivate: { NotchController.shared.activate(geo.displayID) })
                EditorToolbar(displayID: geo.displayID)
            }
        } else {
            Text("No task").opacity(0.5)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.favorites) { f in
                        Button { store.selectedID = f.id; state.tab = .notes } label: {
                            Text(f.title.isEmpty ? "Untitled" : f.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(f.id == store.selectedID ? 0.22 : 0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10))
                .opacity(0.5)
                .rotationEffect(.degrees(90))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .help("Drag to resize")
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { v in
                            if resizeStart == nil { resizeStart = CGSize(width: settings.panelWidth, height: settings.panelHeight) }
                            guard let s = resizeStart else { return }
                            // The panel is centred on the notch, so width grows on both sides: 2x.
                            settings.panelWidth = min(max(s.width + v.translation.width * 2, AppSettings.panelWidthRange.lowerBound), AppSettings.panelWidthRange.upperBound)
                            settings.panelHeight = min(max(s.height + v.translation.height, AppSettings.panelHeightRange.lowerBound), AppSettings.panelHeightRange.upperBound)
                        }
                        .onEnded { _ in resizeStart = nil }
                )
        }
        .frame(height: 22)
    }

    // MARK: Bindings & drop

    private var titleBinding: Binding<String> {
        Binding(get: { store.selectedTask?.title ?? "" },
                set: { if let id = store.selectedID { store.setTitle(id, $0) } })
    }

    private var bodyBinding: Binding<String> {
        Binding(get: { store.selectedTask?.body ?? "" },
                set: { if let id = store.selectedID { store.setBody(id, $0) } })
    }

    @ViewBuilder
    private func dropOverlay(shape: NotchShape, size: CGSize) -> some View {
        if dropTargeted {
            ZStack {
                shape.fill(Color.white.opacity(0.10))
                shape.stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])).foregroundStyle(.white.opacity(0.7))
                Text("Drop to save as card").font(.system(size: 13, weight: .semibold))
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let ns = obj as? NSString else { return }
            let text = ns as String
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    TaskStore.shared.addCard(text)
                    state.tab = .cards
                }
            }
        }
        return true
    }
}

// MARK: - Cards

struct CardsView: View {
    @ObservedObject private var store = TaskStore.shared

    var body: some View {
        if store.cards.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "text.badge.plus").font(.system(size: 22)).opacity(0.5)
                Text("Drag any text onto the notch to save it here.")
                    .font(.system(size: 12)).opacity(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.cards) { card in
                        HStack(alignment: .top, spacing: 8) {
                            Text(card.text)
                                .font(.system(size: 12))
                                .lineLimit(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            VStack(spacing: 6) {
                                Button { store.copyCard(card) } label: { Image(systemName: "doc.on.doc") }
                                    .help("Copy")
                                Button { store.deleteCard(card.id) } label: { Image(systemName: "trash") }
                                    .help("Delete")
                            }
                            .buttonStyle(.plain)
                            .opacity(0.8)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.09)))
                    }
                }
            }
        }
    }
}


// MARK: - Today (calendar)

struct TodayView: View {
    @ObservedObject var state: PanelState
    @ObservedObject private var cal = CalendarService.shared
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    var body: some View {
        Group {
            switch cal.access {
            case .granted:
                if cal.events.isEmpty {
                    placeholder("calendar", "No more events today.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(cal.events) { ev in row(ev) }
                        }
                    }
                }
            case .denied:
                VStack(spacing: 8) {
                    placeholder("calendar.badge.exclamationmark", "Calendar access is off.")
                    Button("Open Calendar privacy settings") { cal.openPrivacySettings() }
                }
            case .unknown:
                VStack(spacing: 8) {
                    placeholder("calendar", "See today\u{2019}s events here and start a note for any meeting.")
                    Button("Connect Calendar") { cal.requestAccess() }
                }
            }
        }
        .onAppear { cal.refreshAuthorization() }
    }

    private func placeholder(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).opacity(0.5)
            Text(text).font(.system(size: 12)).opacity(0.65).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ ev: CalendarService.CalEvent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(ev.isAllDay ? "All day" : Self.timeFormat.string(from: ev.start))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                if !ev.isAllDay {
                    Text(Self.timeFormat.string(from: ev.end)).font(.system(size: 10).monospacedDigit()).opacity(0.55)
                }
            }
            .frame(width: 64, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(ev.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(ev.subtitle).font(.system(size: 10.5)).opacity(0.55).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                let t = cal.noteTask(for: ev)
                TaskStore.shared.selectedID = t.id
                state.tab = .notes
            } label: {
                Label(cal.hasNote(for: ev) ? "Open note" : "Start note", systemImage: cal.hasNote(for: ev) ? "doc.text" : "doc.badge.plus")
                    .labelStyle(.titleAndIcon).font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}
