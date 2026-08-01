import SwiftUI
import QuickLook
import UniformTypeIdentifiers

@MainActor
final class DocumentsViewModel: ObservableObject {
    @Published var documents: [DocumentFile] = []
    @Published var category = "General"
    @Published var previewURL: URL?
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    func reload() async {
        documents = (try? await environment.documents.fetchAll()) ?? []
    }

    func importFile(url: URL) async {
        _ = try? await environment.documents.importFile(from: url, title: "", categoryName: category)
        await reload()
    }

    func delete(_ doc: DocumentFile) async {
        try? await environment.documents.delete(id: doc.id)
        await reload()
    }

    func preview(_ doc: DocumentFile) {
        previewURL = environment.documents.fileURL(for: doc)
    }
}

struct DocumentsView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<DocumentsViewModel>()
    @State private var showImporter = false

    var body: some View {
        Group {
            if let vm = holder.value { DocumentsContent(viewModel: vm, showImporter: $showImporter) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = DocumentsViewModel(environment: environment) } }
    }
}

struct DocumentsContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: DocumentsViewModel
    @Binding var showImporter: Bool

    var body: some View {
        Group {
            if viewModel.documents.isEmpty {
                NothingHereView(
                    image: .emptyDocuments,
                    title: "No documents",
                    detail: "Import files — they are copied into the app so the original can move freely."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.spaceXS) {
                        ForEach(viewModel.documents) { doc in
                            ConsolePanel {
                                Button {
                                    viewModel.preview(doc)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(doc.title).foregroundStyle(palette.text)
                                        Text("\(doc.categoryName) · \(ByteCountFormatter.string(fromByteCount: doc.byteSize, countStyle: .file))")
                                            .font(Theme.captionFont())
                                            .foregroundStyle(palette.secondaryText)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Button("Delete", role: .destructive) {
                                    Task { await viewModel.delete(doc) }
                                }
                                .buttonStyle(ConsoleButtonStyle(kind: .warning))
                            }
                        }
                    }
                    .padding(Theme.spaceM)
                    .padding(.bottom, Theme.consoleBottomClearance)
                }
            }
        }
        .background(palette.background)
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Import") { showImporter = true }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessed = url.startAccessingSecurityScopedResource()
                Task {
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    await viewModel.importFile(url: url)
                }
            }
        }
        .quickLookPreview($viewModel.previewURL)
        .task { await viewModel.reload() }
    }
}
