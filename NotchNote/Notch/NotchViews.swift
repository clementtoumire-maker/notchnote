import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shape & material

/// Flat top (so it fuses with the hardware notch), rounded bottom corners. On notchless displays it is a
/// fully rounded "Dynamic Island" pill.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var hasNotch: Bool
    /// Radius of the small concave "ears" where the notch meets the top edge. The rect handed to `path`
    /// includes `ear` of extra width on each side; the body is inset by it.
    var ear: CGFloat = 0

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        if !hasNotch {
            return RoundedRectangle(cornerRadius: min(bottomRadius, rect.height / 2), style: .continuous).path(in: rect)
        }
        let e = ear
        let b = rect.insetBy(dx: e, dy: 0)
        let r = max(0, min(bottomRadius, b.width / 2, b.height))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if e > 0 { p.addQuadCurve(to: CGPoint(x: b.maxX, y: rect.minY + e), control: CGPoint(x: b.maxX, y: rect.minY)) }
        p.addLine(to: CGPoint(x: b.maxX, y: b.maxY - r))
        p.addArc(tangent1End: CGPoint(x: b.maxX, y: b.maxY),
                 tangent2End: CGPoint(x: b.maxX - r, y: b.maxY), radius: r)
        p.addLine(to: CGPoint(x: b.minX + r, y: b.maxY))
        p.addArc(tangent1End: CGPoint(x: b.minX, y: b.maxY),
                 tangent2End: CGPoint(x: b.minX, y: b.maxY - r), radius: r)
        if e > 0 {
            p.addLine(to: CGPoint(x: b.minX, y: rect.minY + e))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: b.minX, y: rect.minY))
        }
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
        if hasNotch || reduceTransparency || AppSettings.shared.externalStyle == .black {
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
        let ear = state.geometry.hasNotch ? NotchGeometry.earRadius : 0
        let shape = NotchShape(bottomRadius: NotchGeometry.hardwareCornerRadius, hasNotch: state.geometry.hasNotch, ear: ear)
        let unchecked = store.tasks.reduce(0) { $0 + $1.uncheckedCount }
        ZStack(alignment: .top) {
            NotchBackground(hasNotch: state.geometry.hasNotch)
                .frame(width: size.width + 2 * ear, height: size.height)
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

    @ObservedObject private var focus = FocusTimer.shared
    @State private var showTasks = false
    @ObservedObject private var toaster = Toaster.shared
    @State private var editingTitle = false
    @State private var dropTargeted = false
    @State private var resizeStart: CGSize?
    @FocusState private var titleFocused: Bool

    private var geo: NotchGeometry { state.geometry }

    var body: some View {
        let full = geo.expandedSize(settings)
        let collapsed = geo.collapsedSize(settings)
        let size = state.isOpen ? full : collapsed
        let ear = geo.hasNotch ? NotchGeometry.earRadius : 0
        let shape = NotchShape(bottomRadius: state.isOpen ? 26 : (geo.hasNotch ? NotchGeometry.hardwareCornerRadius : 15), hasNotch: geo.hasNotch, ear: ear)
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
            .frame(width: size.width + 2 * ear, height: size.height, alignment: .top)
            .clipShape(shape)
            .modifier(GlassEdge(hasNotch: geo.hasNotch, shape: shape))
            .overlay(dropOverlay(shape: shape, size: CGSize(width: size.width + 2 * ear, height: size.height)))
        }
        .frame(width: full.width + 2 * ear, height: full.height, alignment: .top)
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
        .overlay(alignment: .topLeading) {
            if showTasks {
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001).onTapGesture { showTasks = false }
                    TaskPickerView(isPresented: $showTasks)
                        .padding(.leading, 10)
                        .padding(.top, (geo.hasNotch ? geo.hardwareNotch.height + 4 : 12) + 30)
                        .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let m = toaster.message {
                HStack(spacing: 12) {
                    Text(m).font(.system(size: 12.5)).lineLimit(1)
                    if toaster.hasUndo {
                        Button("Undo") { toaster.undo() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.55, green: 0.72, blue: 1))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                }
                .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 7)
                .background(Capsule().fill(Color(white: 0.16).opacity(0.97)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showTasks)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toaster.message)
        .onChange(of: state.isOpen) { _, open in if !open { showTasks = false } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { showTasks.toggle() } label: {
                Image(systemName: "line.3.horizontal").frame(width: 22, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(0.85)
            .help("Find, switch and create tasks and folders")

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

            if focus.isRunning {
                Menu {
                    Button(focus.paused ? "Resume" : "Pause") { focus.togglePause() }
                    Button("Add 5 minutes") { focus.add(minutes: 5) }
                    Button("Remove 5 minutes") { focus.add(minutes: -5) }
                    Divider()
                    Button("Stop session") { focus.stop() }
                } label: {
                    Text((focus.paused ? "\u{275A}\u{275A} " : "\u{25CF} ") + focus.clock)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9).padding(.vertical, 2)
                        .background(Capsule().fill(Color(red: 1, green: 0.84, blue: 0.04)))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Focus: \(focus.title)")
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
            taskMenu
        }
        .font(.system(size: 13))
    }

    private var taskMenu: some View {
        Menu {
            Button("Rename") { editingTitle = true; DispatchQueue.main.async { titleFocused = true } }
            Button(isFav ? "Remove from favorites" : "Add to favorites") {
                if let id = store.selectedID { store.toggleFavorite(id) }
            }
            Button("Duplicate") { if let id = store.selectedID, store.duplicate(id) != nil { toaster.show("Duplicated") } }
            Button("Clear done items" + ((store.selectedTask?.checkedCount ?? 0) > 0 ? " (\(store.selectedTask?.checkedCount ?? 0))" : "")) { clearDone() }
                .disabled((store.selectedTask?.checkedCount ?? 0) == 0)
            Menu("Move to folder") {
                Button("No folder") { moveSelected(to: "") }
                ForEach(settings.folders, id: \.self) { f in Button(f) { moveSelected(to: f) } }
            }
            Divider()
            Button("Open task window") { WindowManager.shared.showTasks() }
            Button(state.pinned ? "Let the panel close again" : "Keep panel open") { state.pinned.toggle() }
            Divider()
            Button("Delete task", role: .destructive) { deleteSelected() }
        } label: {
            Image(systemName: "ellipsis").frame(width: 22, height: 20).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(0.85)
        .help("This task")
    }

    private func clearDone() {
        guard let id = store.selectedID, let prev = store.selectedTask?.body else { return }
        let n = store.clearDone(id)
        if n > 0 { toaster.show("Cleared \(n) done \(n == 1 ? "item" : "items")") { store.setBody(id, prev) } }
    }

    private func moveSelected(to folder: String) {
        guard let id = store.selectedID, let was = store.selectedTask?.folder else { return }
        store.setFolder(id, folder)
        toaster.show("Moved to " + (folder.isEmpty ? "No folder" : folder)) { store.setFolder(id, was) }
    }

    private func deleteSelected() {
        guard let t = store.selectedTask else { return }
        let idx = store.index(of: t.id)
        store.deleteTask(t.id)
        toaster.show("Deleted \u{201C}\(t.title)\u{201D}") { store.restoreTask(t, at: idx) }
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
            if state.tab == .notes, let t = store.selectedTask, t.checkedCount > 0 {
                Button { clearDone() } label: {
                    Text("Clear \(t.checkedCount) done").font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
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
            iconButton("gearshape", help: "Settings") { WindowManager.shared.showSettings() }
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

// MARK: - Task picker (the ☰ menu)

struct TaskPickerView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var store = TaskStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var query = ""
    @State private var addingFolder = false
    @State private var folderName = ""
    @FocusState private var searchFocused: Bool

    private var results: [NoteTask] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return store.tasks.filter {
            $0.title.lowercased().contains(q) || MarkdownCodec.stripInline($0.body).lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Search or create\u{2026}", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.12)))
                .focused($searchFocused)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        if results.isEmpty {
                            note("No task matches \u{201C}\(query)\u{201D}.")
                            menuButton("Create task \u{201C}\(query)\u{201D}") { create(title: query, folder: "") }
                        } else {
                            header("Results")
                            ForEach(results) { row($0) }
                        }
                    } else {
                        let favs = store.favorites
                        if !favs.isEmpty { header("Favorites"); ForEach(favs) { row($0) } }
                        ForEach(settings.folders, id: \.self) { f in
                            header(f, plus: { create(title: "New task", folder: f) })
                            let items = store.tasks.filter { $0.folder == f }
                            if items.isEmpty { note("Empty folder.") }
                            ForEach(items) { row($0) }
                        }
                        let loose = store.tasks.filter { !settings.folders.contains($0.folder) }
                        if !loose.isEmpty {
                            header(settings.folders.isEmpty ? "Tasks" : "No folder")
                            ForEach(loose) { row($0) }
                        }
                    }
                }
            }
            .frame(maxHeight: 190)
            Divider().opacity(0.4)
            menuButton("\u{FF0B}  New task", kbd: "\u{2318}N") { create(title: "New task", folder: store.selectedTask?.folder ?? "") }
            if addingFolder {
                TextField("Folder name, then Return", text: $folderName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.12)))
                    .onSubmit {
                        let n = folderName.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty, !settings.folders.contains(n) { settings.folders.append(n); Toaster.shared.show("Folder \u{201C}\(n)\u{201D} created") }
                        folderName = ""; addingFolder = false
                    }
            } else {
                menuButton("\u{25A2}  New folder\u{2026}") { addingFolder = true }
            }
        }
        .padding(6)
        .frame(width: 250)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.15).opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    private func create(title: String, folder: String) {
        let t = store.createTask(title: title.trimmingCharacters(in: .whitespaces))
        store.setFolder(t.id, folder)
        isPresented = false
    }

    private func header(_ t: String, plus: (() -> Void)? = nil) -> some View {
        HStack {
            Text(t.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(0.6).opacity(0.6)
            Spacer()
            if let plus {
                Button(action: plus) { Image(systemName: "plus").font(.system(size: 10)) }
                    .buttonStyle(.plain).opacity(0.8).help("New task in \(t)")
            }
        }
        .padding(.horizontal, 8).padding(.top, 7).padding(.bottom, 2)
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).opacity(0.6).padding(.horizontal, 8).padding(.vertical, 3)
    }

    private func menuButton(_ t: String, kbd: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(t).font(.system(size: 12.5)); Spacer(); if let kbd { Text(kbd).font(.system(size: 11)).opacity(0.55) } }
                .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ t: NoteTask) -> some View {
        HStack(spacing: 4) {
            Button {
                store.selectedID = t.id
                isPresented = false
            } label: {
                HStack {
                    Text(t.title.isEmpty ? "Untitled" : t.title).font(.system(size: 12.5)).lineLimit(1)
                    Spacer()
                    if t.uncheckedCount > 0 { Text("\(t.uncheckedCount)").font(.system(size: 11).monospacedDigit()).opacity(0.55) }
                }
                .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(t.id == store.selectedID ? 0.2 : 0)))
            }
            .buttonStyle(.plain)
            Button {
                let idx = store.index(of: t.id)
                store.deleteTask(t.id)
                Toaster.shared.show("Deleted \u{201C}\(t.title)\u{201D}") { store.restoreTask(t, at: idx) }
            } label: { Image(systemName: "trash").font(.system(size: 11)).opacity(0.6) }
            .buttonStyle(.plain)
            .help("Delete \u{201C}\(t.title)\u{201D}")
        }
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


// MARK: - Today (plan the day)

struct TodayView: View {
    @ObservedObject var state: PanelState
    @ObservedObject private var cal = CalendarService.shared
    @ObservedObject private var store = TaskStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var focus = FocusTimer.shared
    @State private var quick = ""
    @State private var tagFilter: String?

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    private var allItems: [PlanItem] { Planner.items(from: store.tasks) }
    private var items: [PlanItem] {
        guard let t = tagFilter else { return allItems }
        return allItems.filter { $0.tags.contains(t) }
    }
    private var todayItems: [PlanItem] {
        let t = items.filter { $0.isToday }
        return t.filter { !$0.checked } + t.filter { $0.checked }
    }
    private var suggestions: [PlanItem] { Array(items.filter { !$0.checked && !$0.hasDate }.prefix(5)) }
    private var tags: [String] { Array(Set(allItems.flatMap { $0.tags })).sorted() }
    private var plannedMinutes: Int { items.filter { $0.isToday && !$0.checked }.reduce(0) { $0 + $1.minutes } }
    private var meetingMinutes: Int {
        guard cal.access == .granted else { return 0 }
        return cal.events.filter { !$0.isAllDay }.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
    }

    var body: some View {
        let limit = settings.dailyLimitHours * 60
        let over = plannedMinutes > limit
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Today").font(.system(size: 15, weight: .bold))
                    let done = todayItems.filter { $0.checked }.count
                    Text("\(done) of \(todayItems.count) done \u{00B7} planned \(fmt(plannedMinutes)) of \(settings.dailyLimitHours)h"
                         + (meetingMinutes > 0 ? " \u{00B7} \(fmt(meetingMinutes)) in meetings" : ""))
                        .font(.system(size: 11.5).monospacedDigit()).opacity(0.65)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(over ? Color.red : yellow)
                            .frame(width: g.size.width * min(1, CGFloat(plannedMinutes) / CGFloat(max(limit, 1))))
                    }
                }
                .frame(height: 5)
                if over {
                    Text("That is over your \(settings.dailyLimitHours) hour limit. Move something to tomorrow with the arrow.")
                        .font(.system(size: 11.5)).foregroundStyle(Color(red: 1, green: 0.82, blue: 0.8))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.2)))
                }
                if !tags.isEmpty { tagBar }
                agenda
                section("To do today")
                TextField("Add to today\u{2026} e.g. call the client p1 30m #work", text: $quick)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                    .onSubmit {
                        Planner.addToday(quick)
                        quick = ""
                    }
                if todayItems.isEmpty {
                    Text("Nothing planned. Type above, or pick from the suggestions.")
                        .font(.system(size: 11)).opacity(0.6).padding(.horizontal, 8)
                }
                ForEach(todayItems) { row($0, suggestion: false) }
                if !suggestions.isEmpty {
                    section("Suggestions")
                    ForEach(suggestions) { row($0, suggestion: true) }
                }
            }
            .padding(.trailing, 2)
        }
        .onAppear { cal.refreshAuthorization() }
    }

    private var yellow: Color { Color(red: 1, green: 0.84, blue: 0.04) }

    private func fmt(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        return h > 0 ? (r > 0 ? "\(h)h \(r)m" : "\(h)h") : "\(r)m"
    }

    private func section(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(0.6).opacity(0.55).padding(.top, 6).padding(.leading, 2)
    }

    private var tagBar: some View {
        HStack(spacing: 4) {
            chip("All", selected: tagFilter == nil) { tagFilter = nil }
            ForEach(tags, id: \.self) { t in chip("#" + t, selected: tagFilter == t) { tagFilter = t } }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ t: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 11.5)).padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.24 : 0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Agenda

    @ViewBuilder private var agenda: some View {
        switch cal.access {
        case .granted:
            if !cal.events.isEmpty {
                section("Agenda")
                ForEach(cal.events) { eventRow($0) }
            }
        case .denied:
            Button("Calendar access is off. Open privacy settings") { cal.openPrivacySettings() }
                .buttonStyle(.plain).font(.system(size: 11.5)).padding(.vertical, 4).opacity(0.8)
        case .unknown:
            Button { cal.requestAccess() } label: {
                Text("Connect Calendar to see meetings here").font(.system(size: 11.5)).frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
    }

    private func eventRow(_ ev: CalendarService.CalEvent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(ev.isAllDay ? "All day" : Self.timeFormat.string(from: ev.start))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                if !ev.isAllDay {
                    Text(Self.timeFormat.string(from: ev.end)).font(.system(size: 10).monospacedDigit()).opacity(0.55)
                }
            }
            .frame(width: 56, alignment: .trailing)
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
                Text(cal.hasNote(for: ev) ? "Open note" : "Start note").font(.system(size: 11))
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    // MARK: Items

    private func row(_ item: PlanItem, suggestion: Bool) -> some View {
        HStack(spacing: 8) {
            Button { Planner.toggle(item) } label: {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5).opacity(item.checked ? 0 : 1)
                    Circle().fill(yellow).opacity(item.checked ? 1 : 0)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.black).opacity(item.checked ? 1 : 0)
                }
                .frame(width: 17, height: 17)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.text).font(.system(size: 12.5)).lineLimit(1)
                    .strikethrough(item.checked).opacity(item.checked ? 0.45 : 1)
                Text(subtitle(item)).font(.system(size: 10.5)).opacity(0.55).lineLimit(1)
            }
            Spacer(minLength: 4)
            if suggestion {
                pill("\u{FF0B} Today") { Planner.planForToday(item) }
            } else if !item.checked {
                pill("\u{25B6} \(settings.focusMinutes)m") { focus.start(item.text, minutes: settings.focusMinutes) }
                Menu {
                    ForEach([10, 15, 25, 45, 50, 60, 90], id: \.self) { m in
                        Button("\(m) minutes") { focus.start(item.text, minutes: m) }
                    }
                } label: {
                    Image(systemName: "timer").font(.system(size: 11)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Choose the focus length")
                Button { Planner.moveToTomorrow(item) } label: {
                    Image(systemName: "arrow.right").font(.system(size: 11)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("Move to tomorrow")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func pill(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 11)).padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ i: PlanItem) -> String {
        var parts = [i.taskTitle]
        switch i.priority { case "h": parts.append("High"); case "m": parts.append("Medium"); case "l": parts.append("Low"); default: break }
        if i.minutes > 0 { parts.append(fmt(i.minutes)) }
        return parts.joined(separator: " \u{00B7} ")
    }
}
