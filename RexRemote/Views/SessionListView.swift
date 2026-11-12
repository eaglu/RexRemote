import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var store: SessionViewModel
    let zoomNamespace: Namespace.ID
    @State private var selected: SessionRef?
    @State private var renaming: SessionRef?
    @State private var newLabel: String = ""
    @State private var showServer = false
    @State private var creatingSession = false
    @State private var newSessionLabel = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let view = store.view, let window = view.activeWindow {
                    nowCard(view: view, window: window)
                }
                sessionsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(RexTheme.paper.ignoresSafeArea())
        .navigationTitle(store.host.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    connection.disconnect()
                } label: {
                    Image(systemName: "bolt.slash")
                        .foregroundStyle(RexTheme.ink)
                }
                .accessibilityIdentifier("disconnectButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    Button {
                        Task { await store.refreshSessions() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(RexTheme.ink)
                    }
                    .accessibilityIdentifier("refreshSessionsButton")
                    Button {
                        showServer = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(RexTheme.ink)
                    }
                    .accessibilityIdentifier("serverInfoButton")
                }
            }
        }
        .refreshable {
            await store.refreshSessions()
        }
        .task {
            await store.refreshSessions()
        }
        .navigationDestination(item: $selected) { session in
            SessionScreen(session: session, zoomNamespace: zoomNamespace)
        }
        .sheet(isPresented: $showServer) {
            ServerSheet(connection: connection)
        }
        .alert("New session", isPresented: $creatingSession) {
            TextField("Label", text: $newSessionLabel)
            Button("Cancel", role: .cancel) { newSessionLabel = "" }
            Button("Create") {
                let label = newSessionLabel.trimmingCharacters(in: .whitespaces)
                newSessionLabel = ""
                Task {
                    guard let id = await store.createSession(label: label.isEmpty ? "phone" : label) else { return }
                    if let created = store.sessions.first(where: { $0.id == id }) {
                        selected = created
                    }
                }
            }
        }
        .alert("Rename session", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Label", text: $newLabel)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let session = renaming {
                    Task { await store.renameSession(session.id, label: newLabel) }
                }
                renaming = nil
            }
        }
    }

    // MARK: - Now

    private func nowCard(view: SessionView, window: WindowInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RexTheme.secondaryInk)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(">_")
                        .font(RexTheme.mono(12, weight: .bold))
                        .foregroundStyle(RexTheme.mintDeep)
                    Text(view.label)
                        .font(RexTheme.text(.headline, weight: .semibold))
                        .foregroundStyle(RexTheme.ink)
                    Spacer()
                    Text("\(view.windows.count) windows · \(view.allBlocks.count) panes")
                        .font(RexTheme.mono(10))
                        .foregroundStyle(RexTheme.secondaryInk)
                }

                HStack(spacing: 4) {
                    ForEach(view.windows.prefix(4)) { candidate in
                        HStack(spacing: 5) {
                            Text(candidate.label)
                                .font(.system(size: 11, weight: candidate.id == window.id ? .semibold : .regular))
                            Text("\(candidate.panes.count)")
                                .font(RexTheme.mono(9))
                        }
                        .foregroundStyle(candidate.id == window.id ? RexTheme.chipInk : RexTheme.secondaryInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            candidate.id == window.id ? AnyShapeStyle(RexTheme.chip) : AnyShapeStyle(RexTheme.strip),
                            in: Capsule()
                        )
                    }
                    if view.windows.count > 4 {
                        Text("+\(view.windows.count - 4)")
                            .font(RexTheme.mono(9))
                            .foregroundStyle(RexTheme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }

                if let pane = window.pane(id: window.focusedBlockID) {
                    Text("Active pane · \(pane.block.label)")
                        .font(.caption2)
                        .foregroundStyle(RexTheme.secondaryInk)
                }
            }
            .padding(12)
            .rexCard(radius: 12)
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sessions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RexTheme.secondaryInk)

            if store.sessions.isEmpty {
                Text("No sessions yet. Ask Rex on your Mac to start one.")
                    .font(.footnote)
                    .foregroundStyle(RexTheme.secondaryInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rexCard(radius: 12)
            }

            VStack(spacing: 8) {
                ForEach(store.sessions) { session in
                    row(session)
                }
                Button {
                    creatingSession = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(RexTheme.text(.callout))
                            .foregroundStyle(RexTheme.mintDeep)
                        Text("New session")
                            .font(RexTheme.text(.subheadline, weight: .medium))
                            .foregroundStyle(RexTheme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RexTheme.card, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(RexTheme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newSessionButton")
            }
        }
    }

    private func row(_ session: SessionRef) -> some View {
        Button {
            selected = session
        } label: {
            HStack(spacing: 10) {
                Text(">_")
                    .font(RexTheme.mono(11, weight: .bold))
                    .foregroundStyle(session.id == store.currentSessionID ? RexTheme.mintDeep : RexTheme.secondaryInk.opacity(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.label)
                        .font(RexTheme.text(.subheadline, weight: .medium))
                        .foregroundStyle(RexTheme.ink)
                    Text(shortID(session.id))
                        .font(RexTheme.mono(10))
                        .foregroundStyle(RexTheme.secondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(RexTheme.text(.caption, weight: .semibold))
                    .foregroundStyle(RexTheme.secondaryInk.opacity(0.6))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rexCard(radius: 12)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: session.id, in: zoomNamespace)
        .accessibilityLabel(session.label)
        .accessibilityIdentifier("sessionRow")
        .contextMenu {
            Button("Rename session…") {
                renaming = session
                newLabel = session.label
            }
            Button("Destroy session", role: .destructive) {
                Task { await store.destroySession(session.id) }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await store.destroySession(session.id) }
            } label: {
                Label("Destroy", systemImage: "trash")
            }
        }
    }

    private func shortID(_ id: String) -> String {
        id.replacingOccurrences(of: "session:", with: "").prefix(8).description
    }
}
