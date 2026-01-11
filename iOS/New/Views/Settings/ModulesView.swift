//
//  ModulesView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import SwiftUI

struct ModulesView: View {
    @State private var modules: [ScrapingModule] = ModuleManager.shared.modules
    @State private var loading = false
    @State private var showAddModuleFailAlert = false
    @State private var showModuleAdditionSheet = false
    @State private var moduleUrlToAdd: String = ""

    var body: some View {
        List {
            Section {
                ForEach(modules, id: \.id) { module in
                    moduleItem(module: module)
                }
                .onDelete(perform: delete)
            }
        }
        .overlay {
            if loading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.secondary)
            }
        }
        .navigationTitle(NSLocalizedString("PLAYER_SOURCES"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAlert()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(NSLocalizedString("MODULE_ADD_FAIL"), isPresented: $showAddModuleFailAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .moduleAdded)) { _ in
            withAnimation {
                modules = ModuleManager.shared.modules
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .moduleRemoved)) { _ in
            withAnimation {
                modules = ModuleManager.shared.modules
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .moduleStateChanged)) { _ in
            withAnimation {
                modules = ModuleManager.shared.modules
            }
        }
        .task {
            // Load modules on appear
            modules = ModuleManager.shared.modules
        }
    }

    func moduleItem(module: ScrapingModule) -> some View {
        HStack(spacing: 12) {
            // Module icon
            AsyncImage(url: URL(string: module.metadata.iconUrl)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "tv.fill")
                                .foregroundStyle(.gray)
                        )
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "tv.fill")
                                .foregroundStyle(.gray)
                        )
                @unknown default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(module.metadata.sourceName)
                    .font(.headline)

                Text(module.metadata.author.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(module.metadata.version)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(module.metadataUrl)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button {
                toggleModuleActive(module)
            } label: {
                Label(
                    module.isActive ? NSLocalizedString("DISABLE") : NSLocalizedString("ENABLE"),
                    systemImage: module.isActive ? "pause.circle" : "play.circle"
                )
            }

            Button(role: .destructive) {
                ModuleManager.shared.deleteModule(module)
            } label: {
                Label(NSLocalizedString("REMOVE"), systemImage: "trash")
            }

            Button {
                UIPasteboard.general.string = module.metadataUrl
            } label: {
                Label(NSLocalizedString("COPY_URL"), systemImage: "doc.on.doc")
            }
        }
    }

    func delete(at offsets: IndexSet) {
        let modulesToDelete = offsets.map { modules[$0] }
        for module in modulesToDelete {
            ModuleManager.shared.deleteModule(module)
        }
    }

    func toggleModuleActive(_ module: ScrapingModule) {
        // Find the module in the shared manager and toggle it
        if let index = ModuleManager.shared.modules.firstIndex(where: { $0.id == module.id }) {
            var updatedModule = ModuleManager.shared.modules[index]
            updatedModule.isActive.toggle()
            ModuleManager.shared.modules[index] = updatedModule
            ModuleManager.shared.saveModules()
            modules = ModuleManager.shared.modules
            // Notify that module state changed
            NotificationCenter.default.post(name: .moduleStateChanged, object: module.id.uuidString)
        }
    }

    func addModule(url: String) {
        guard !url.isEmpty else { return }
        guard URL(string: url) != nil else {
            showAddModuleFailAlert = true
            return
        }

        Task {
            loading = true
            do {
                _ = try await ModuleManager.shared.addModule(metadataUrl: url)
                await MainActor.run {
                    modules = ModuleManager.shared.modules
                    loading = false
                }
            } catch {
                await MainActor.run {
                    loading = false
                    showAddModuleFailAlert = true
                }
            }
        }
    }

    func showAlert() {
        var alertTextField: UITextField?
        (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
            title: NSLocalizedString("MODULE_ADD"),
            message: NSLocalizedString("MODULE_ADD_TEXT"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("ADD"), style: .default) { _ in
                    guard let text = alertTextField?.text, !text.isEmpty else { return }
                    addModule(url: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("MODULE_URL")
                    textField.keyboardType = .URL
                    textField.autocorrectionType = .no
                    textField.autocapitalizationType = .none
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ]
        )
    }
}

#Preview {
    ModulesView()
}
