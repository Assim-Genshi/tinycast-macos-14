import AppKit
import SwiftUI

public struct FileList: View {
    public let results: [FileSearchItem]
    public let selectedID: String?
    public let scroll: ScrollIntent
    public let onSelect: (FileSearchItem) -> Void
    public let onActivate: (FileSearchItem) -> Void
    public let onActions: (FileSearchItem) -> Void

    public init(
        results: [FileSearchItem],
        selectedID: String?,
        scroll: ScrollIntent,
        onSelect: @escaping (FileSearchItem) -> Void,
        onActivate: @escaping (FileSearchItem) -> Void,
        onActions: @escaping (FileSearchItem) -> Void
    ) {
        self.results = results
        self.selectedID = selectedID
        self.scroll = scroll
        self.onSelect = onSelect
        self.onActivate = onActivate
        self.onActions = onActions
    }

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: "Files (\(results.count))", isFirst: true)
                    ForEach(results) { item in
                        FileRow(item: item, selected: item.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(item) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(item)
                                    onActivate(item)
                                }
                            )
                            .onRightClick { onActions(item) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Size.bottomBarHeight + Theme.Spacing.xs)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: scroll) { _, scroll in
                switch scroll.kind {
                case .top:
                    proxy.scrollToOrigin()
                case .follow:
                    if firstRowSelected {
                        proxy.scrollToOrigin()
                    } else if let selectedID {
                        proxy.reveal(selectedID)
                    }
                }
            }
        }
    }
}

public struct FileRow: View {
    public let item: FileSearchItem
    public let selected: Bool

    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            FileIconView(item: item)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Text(item.abbreviatedParentPath)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !item.formattedSize.isEmpty {
                Text(item.formattedSize)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }

            Text(item.formattedDate)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row)
                .fill(fill)
        )
        .onHover { isHovered in
            if AppCore.shared.palette.hoverHighlightArmed {
                hovered = isHovered
            } else if !isHovered {
                hovered = false
            }
        }
    }
}

public struct FileIconView: View {
    public let item: FileSearchItem
    @State private var image: NSImage?

    public init(item: FileSearchItem) {
        self.item = item
        _image = State(initialValue: IconCache.cached(forFile: item.path))
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: item.path) {
            image = await IconCache.loadAsync(forFile: item.path)
        }
    }
}

public enum FileActionsMenu {
    public static func content(item: FileSearchItem, core: AppCore) -> PopoverMenuContent {
        let openTitle = item.isDirectory ? "Open Folder" : "Open File"
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(title: openTitle, systemImage: "arrow.up.forward.app", shortcut: "↵") {
                core.openFile(item)
            },
            PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {
                core.revealInFinder(item)
            },
            PopoverMenuItem(title: "Copy Path", systemImage: "doc.on.doc", shortcut: "⌘C") {
                core.copyFilePath(item)
            },
            PopoverMenuItem(title: "Copy File", systemImage: "doc.badge.plus", shortcut: "⌘⇧C") {
                core.copyFile(item)
            }
        ]

        if item.isDirectory {
            items.append(
                PopoverMenuItem(title: "Open in Terminal", systemImage: "terminal", shortcut: "⌃T") {
                    core.openInTerminal(item)
                }
            )
        }

        items.append(
            PopoverMenuItem(title: "Move to Trash", systemImage: "trash", shortcut: "⌘⌫", isDestructive: true) {
                core.trashFile(item)
            }
        )

        return PopoverMenuContent(header: item.name, items: items)
    }
}
