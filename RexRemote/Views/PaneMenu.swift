import SwiftUI
import UIKit

/// Everything you can do to one pane without leaving the phone.
///
/// The order follows what a phone actually needs: clipboard first, then the
/// things that fix a broken pane (clear, reset), then layout moves, then the
/// destructive one last.
struct PaneMenu: View {
    @EnvironmentObject private var store: AppStore

    let blockID: String
    let siblings: [PanePlacement]
    let windows: [WindowInfo]
    let isZoomed: Bool
    let onRename: () -> Void
    let onNotice: (String) -> Void

    var body: some View {
        Menu {
            Button("Copy") { store.copySelection(blockID: blockID) }
            Button("Paste") { store.pasteClipboard(blockID: blockID) }
            Button("Rename pane…") { onRename() }

            Divider()

            Button("Copy working directory") {
                Task {
                    guard let payload = await store.terminalInfo("pwd", blockID: blockID),
                          let path = payload.string("cwd") ?? payload.string("pwd") else { return }
                    UIPasteboard.general.string = path
                    onNotice("Copied \(path)")
                }
            }
            Button("Clear scrollback") { Task { await store.clearBlock(blockID) } }
            Button("Reset terminal") { Task { await store.resetBlock(blockID) } }

            Divider()

            Button(isZoomed ? "Unzoom pane" : "Zoom pane") {
                store.toggleZoom(blockID: blockID)
            }
            Button("Float pane") { Task { await store.floatBlock(blockID) } }

            if !siblings.isEmpty {
                Menu("Swap with") {
                    ForEach(siblings) { other in
                        Button(other.block.label) {
                            Task { await store.swapBlocks(blockID, with: other.id) }
                        }
                    }
                }
                Menu("Move beside") {
                    ForEach(siblings) { other in
                        Button("\(other.block.label) · left") {
                            Task {
                                await store.moveBlock(blockID, to: other.id, direction: "horizontal", side: "before")
                            }
                        }
                        Button("\(other.block.label) · right") {
                            Task {
                                await store.moveBlock(blockID, to: other.id, direction: "horizontal", side: "after")
                            }
                        }
                        Button("\(other.block.label) · above") {
                            Task {
                                await store.moveBlock(blockID, to: other.id, direction: "vertical", side: "before")
                            }
                        }
                        Button("\(other.block.label) · below") {
                            Task {
                                await store.moveBlock(blockID, to: other.id, direction: "vertical", side: "after")
                            }
                        }
                    }
                }
            }

            if !windows.isEmpty {
                Menu("Move to window") {
                    ForEach(windows) { candidate in
                        Button(candidate.label) {
                            Task {
                                guard let anchor = candidate.panes.first?.id else { return }
                                await store.moveBlock(blockID, to: anchor, direction: "horizontal", side: "after")
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Split right") {
                Task { await store.split(blockID: blockID, direction: "horizontal") }
            }
            Button("Split down") {
                Task { await store.split(blockID: blockID, direction: "vertical") }
            }
            Button("New pane beside") {
                Task { await store.newBlock(beside: blockID, direction: "horizontal") }
            }

            Divider()

            Button("Send Mac clipboard") {
                Task {
                    guard let text = await store.readRemoteClipboard(blockID: blockID) else {
                        onNotice("Mac clipboard is empty")
                        return
                    }
                    UIPasteboard.general.string = text
                    onNotice("Copied \(text.count) characters from the Mac")
                }
            }

            Divider()

            Button("Close pane", role: .destructive) {
                Task { await store.closeBlock(blockID) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RexTheme.secondaryInk)
                .frame(width: 26, height: 30)
        }
        .accessibilityIdentifier("paneMenuButton")
    }
}
