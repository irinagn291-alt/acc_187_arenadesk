import SwiftUI

@MainActor
final class NotesViewModel: ObservableObject {
    @Published var notes: [Note] = []
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }
    func reload() async { notes = (try? await environment.notes.fetchAll()) ?? [] }
}

struct NotesView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<NotesViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { NotesContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = NotesViewModel(environment: environment) } }
    }
}

struct NotesContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spaceXS) {
                ForEach(viewModel.notes) { note in
                    NavigationLink {
                        NoteEditorView(note: note) { await viewModel.reload() }
                    } label: {
                        ConsolePanel {
                            HStack {
                                if note.isPinned {
                                    Image(systemName: "pin.fill").foregroundStyle(palette.primary)
                                }
                                Text(note.title).foregroundStyle(palette.text)
                            }
                            Text(note.body).lineLimit(2).font(Theme.captionFont()).foregroundStyle(palette.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Add") {
                    NoteEditorView(note: nil) { await viewModel.reload() }
                }
            }
        }
        .task { await viewModel.reload() }
    }
}

struct NoteEditorView: View {
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let note: Note?
    var onSave: () async -> Void
    @State private var title = ""
    @State private var bodyText = ""
    @State private var isPinned = false

    var body: some View {
        ScrollView {
            ConsolePanel(title: "Note") {
                TextField("Title", text: $title)
                TextField("Body", text: $bodyText, axis: .vertical).lineLimit(5...12)
                Toggle("Pinned", isOn: $isPinned)
            }
            .padding(Theme.spaceM)
        }
        .background(palette.background)
        .navigationTitle(note == nil ? "New note" : "Edit note")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
            }
        }
        .onAppear {
            if let note {
                title = note.title
                bodyText = note.body
                isPinned = note.isPinned
            }
        }
    }

    private func save() async {
        let now = Date()
        let saved = Note(
            id: note?.id ?? UUID(),
            title: title,
            body: bodyText,
            isPinned: isPinned,
            createdAt: note?.createdAt ?? now,
            updatedAt: now
        )
        try? await environment.notes.upsert(saved)
        await onSave()
        dismiss()
    }
}
