//
//  SettingsView.swift
//  Aidoku
//
//  Created by Skitty on 9/17/25.
//

import AidokuRunner
import Nuke
import SwiftUI
import WebKit

struct SettingsView: View {
    @State private var categories: [String]
    @State private var playerCategories: [String]

    @State private var searchText: String = ""
    @State private var searchResult: SettingSearchResult?

    @EnvironmentObject private var path: NavigationCoordinator

    static let settings = Settings.settings

    init() {
        self._categories = State(initialValue: CoreDataManager.shared.getCategoryTitles())
        self._playerCategories = State(initialValue: UserDefaults.standard.stringArray(forKey: "PlayerLibrary.categoriesList") ?? [])
    }
}

extension SettingsView {
    var body: some View {
        List {
            if searchText.isEmpty {
                ForEach(Self.settings.indices, id: \.self) { offset in
                    let setting = Self.settings[offset]
                    SettingView(setting: setting, onChange: onSettingChange)
                        .settingPageContent(pageContentHandler)
                        .settingCustomContent(customContentHandler)
                }
            } else if let searchResult {
                Group {
                    ForEach(searchResult.sections, id: \.id) { section in
                        Section {
                            ForEach(section.paths.indices, id: \.self) { offset in
                                let setting = section.paths[offset]
                                if setting.paths.count == 1, let setting = setting.setting {
                                    // if it's root level, just show itself
                                    SettingView(setting: setting, onChange: onSettingChange)
                                        .settingPageContent(pageContentHandler)
                                        .settingCustomContent(customContentHandler)
                                } else {
                                    Button {
                                        openSearchPage(for: setting)
                                    } label: {
                                        NavigationLink(destination: EmptyView()) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(setting.title.highlight(text: searchText))

                                                HStack(spacing: 2) {
                                                    ForEach(Array(zip(setting.paths.indices, setting.paths)), id: \.0.self) { index, title in
                                                        Text(title)
                                                            .lineLimit(1)
                                                        if index < setting.paths.count - 1 {
                                                            Image(systemName: "arrow.forward")
                                                        }
                                                    }
                                                }
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                        } header: {
                            if section.icon != nil || section.header != nil {
                                HStack {
                                    if let icon = section.icon {
                                        Group {
                                            let iconSize: CGFloat = 29
                                            switch icon {
                                                case .system(let name, let color, let inset):
                                                    Image(systemName: name)
                                                        .resizable()
                                                        .renderingMode(.template)
                                                        .foregroundStyle(.white)
                                                        .aspectRatio(contentMode: .fit)
                                                        .padding(CGFloat(inset))
                                                        .frame(width: iconSize, height: iconSize)
                                                        .background(color.toColor())
                                                        .clipShape(RoundedRectangle(cornerRadius: 6.5))
                                                case .url(let string):
                                                    SourceImageView(
                                                        imageUrl: string,
                                                        width: iconSize,
                                                        height: iconSize,
                                                        downsampleWidth: iconSize * 2
                                                    )
                                                    .clipShape(RoundedRectangle(cornerRadius: 6.5))
                                            }
                                        }
                                        .scaleEffect(0.75)
                                    }
                                    if let header = section.header {
                                        Text(header)
                                    }
                                    Spacer()
                                }
                            }

                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if let searchResult, searchResult.sections.isEmpty {
                UnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText)
        .navigationTitle(NSLocalizedString("SETTINGS"))
        .onChange(of: searchText) { _ in
            search()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateCategories)) { _ in
            categories = CoreDataManager.shared.getCategoryTitles()
            if
                let selected = UserDefaults.standard.string(forKey: "Library.defaultCategory"),
                !selected.isEmpty && selected != "none" && !categories.contains(selected)
            {
                UserDefaults.standard.removeObject(forKey: "Library.defaultCategory")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .updatePlayerCategories)) { _ in
            playerCategories = UserDefaults.standard.stringArray(forKey: "PlayerLibrary.categoriesList") ?? []
            if
                let selected = UserDefaults.standard.string(forKey: "PlayerLibrary.defaultCategory"),
                !selected.isEmpty && selected != "none" && !playerCategories.contains(selected)
            {
                UserDefaults.standard.removeObject(forKey: "PlayerLibrary.defaultCategory")
            }
        }
    }
}

private struct PlayerCategoriesView: View {
    @State private var categories: [String]

    @State private var showRenameFailedAlert = false

    init() {
        self._categories = State(initialValue: UserDefaults.standard.stringArray(forKey: "PlayerLibrary.categoriesList") ?? [])
    }

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                Text(category)
                    .swipeActions {
                        Button(role: .destructive) {
                            onDelete(at: IndexSet(integer: categories.firstIndex(of: category)!))
                        } label: {
                            Label(NSLocalizedString("DELETE"), systemImage: "trash")
                        }
                        Button {
                            showRenamePrompt(targetRenameCategory: category)
                        } label: {
                            Label(NSLocalizedString("RENAME"), systemImage: "pencil")
                        }
                        .tint(.indigo)
                    }
            }
            .onDelete(perform: onDelete)
            .onMove(perform: onMove)
        }
        .animation(.default, value: categories)
        .environment(\.editMode, Binding.constant(.active))
        .navigationTitle(NSLocalizedString("CATEGORIES"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddPrompt()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(NSLocalizedString("RENAME_CATEGORY_FAIL"), isPresented: $showRenameFailedAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("RENAME_CATEGORY_FAIL_INFO"))
        }
    }

    private func saveAndNotify() {
        UserDefaults.standard.set(categories, forKey: "PlayerLibrary.categoriesList")
        NotificationCenter.default.post(name: .updatePlayerCategories, object: nil)
    }

    func onDelete(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            let removedCategory = categories[offset]
            categories.remove(at: offset)

            var locked = UserDefaults.standard.stringArray(forKey: "PlayerLibrary.lockedCategories") ?? []
            locked.removeAll(where: { $0 == removedCategory })
            UserDefaults.standard.set(locked, forKey: "PlayerLibrary.lockedCategories")

            if UserDefaults.standard.string(forKey: "PlayerLibrary.defaultCategory") == removedCategory {
                UserDefaults.standard.removeObject(forKey: "PlayerLibrary.defaultCategory")
            }

            var itemCategories = UserDefaults.standard.dictionary(forKey: "PlayerLibrary.itemCategories") as? [String: [String]] ?? [:]
            itemCategories = itemCategories.mapValues { values in
                values.filter { $0 != removedCategory }
            }
            UserDefaults.standard.set(itemCategories, forKey: "PlayerLibrary.itemCategories")
        }
        saveAndNotify()
    }

    func onMove(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        saveAndNotify()
    }

    func showAddPrompt() {
        var alertTextField: UITextField?
        (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
            title: NSLocalizedString("CATEGORY_ADD"),
            message: NSLocalizedString("CATEGORY_ADD_TEXT"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    addCategory(title: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("CATEGORY_NAME")
                    textField.autocorrectionType = .no
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ],
            textFieldDisablesLastActionWhenEmpty: true
        )
    }

    func showRenamePrompt(targetRenameCategory: String) {
        var alertTextField: UITextField?
        (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
            title: NSLocalizedString("RENAME_CATEGORY"),
            message: NSLocalizedString("RENAME_CATEGORY_INFO"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    renameCategory(title: targetRenameCategory, newTitle: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("CATEGORY_NAME")
                    textField.autocorrectionType = .no
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ],
            textFieldDisablesLastActionWhenEmpty: true
        )
    }

    func addCategory(title: String) {
        guard !title.isEmpty, title.lowercased() != "none", !categories.contains(title) else { return }
        categories.append(title)
        saveAndNotify()
    }

    func renameCategory(title: String, newTitle: String) {
        guard !(newTitle.lowercased() == "none" || categories.contains(newTitle) || newTitle.isEmpty) else {
            showRenameFailedAlert = true
            return
        }
        guard let index = categories.firstIndex(of: title) else { return }
        categories[index] = newTitle

        if UserDefaults.standard.string(forKey: "PlayerLibrary.defaultCategory") == title {
            UserDefaults.standard.set(newTitle, forKey: "PlayerLibrary.defaultCategory")
        }

        var locked = UserDefaults.standard.stringArray(forKey: "PlayerLibrary.lockedCategories") ?? []
        if let oldIndex = locked.firstIndex(of: title) {
            locked[oldIndex] = newTitle
            UserDefaults.standard.set(locked, forKey: "PlayerLibrary.lockedCategories")
        }

        var itemCategories = UserDefaults.standard.dictionary(forKey: "PlayerLibrary.itemCategories") as? [String: [String]] ?? [:]
        itemCategories = itemCategories.mapValues { values in
            values.map { $0 == title ? newTitle : $0 }
        }
        UserDefaults.standard.set(itemCategories, forKey: "PlayerLibrary.itemCategories")

        saveAndNotify()
    }
}

extension SettingsView {
    func onSettingChange(_ key: String) {
        switch key {
            case "General.appearance", "General.useSystemAppearance":
                if !UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                    if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                        UIApplication.shared.firstKeyWindow?.overrideUserInterfaceStyle = .light
                    } else {
                        UIApplication.shared.firstKeyWindow?.overrideUserInterfaceStyle = .dark
                    }
                } else {
                    UIApplication.shared.firstKeyWindow?.overrideUserInterfaceStyle = .unspecified
                }

            case "Advanced.clearTrackedManga":
                confirmAction(
                    title: NSLocalizedString("CLEAR_TRACKED_MANGA"),
                    message: NSLocalizedString("CLEAR_TRACKED_MANGA_TEXT")
                ) {
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearTracks(context: context)
                            try? context.save()
                        }
                    }
                }
            case "Advanced.clearNetworkCache":
                var totalCacheSize = URLCache.shared.currentDiskUsage
                if let nukeCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
                    totalCacheSize += nukeCache.totalSize
                }
                let message = NSLocalizedString("CLEAR_NETWORK_CACHE_TEXT")
                    + "\n\n"
                    + String(
                        format: NSLocalizedString("CACHE_SIZE_%@"),
                        ByteCountFormatter.string(fromByteCount: Int64(totalCacheSize), countStyle: .file)
                    )

                confirmAction(
                    title: NSLocalizedString("CLEAR_NETWORK_CACHE"),
                    message: message
                ) {
                    self.clearNetworkCache()
                }
            case "Advanced.clearReadHistory":
                confirmAction(
                    title: NSLocalizedString("CLEAR_READ_HISTORY"),
                    message: NSLocalizedString("CLEAR_READ_HISTORY_TEXT")
                ) {
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearHistory(context: context)
                            try? context.save()
                        }
                        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
                    }
                }
            case "Advanced.clearExcludingLibrary":
                confirmAction(
                    title: NSLocalizedString("CLEAR_EXCLUDING_LIBRARY"),
                    message: NSLocalizedString("CLEAR_EXCLUDING_LIBRARY_TEXT")
                ) {
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearHistoryExcludingLibrary(context: context)
                            try? context.save()
                        }
                        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
                    }
                }
            case "Advanced.migrateHistory":
                confirmAction(
                    title: "Migrate Chapter History",
                    // swiftlint:disable:next line_length
                    message: "This will migrate leftover reading history from old versions that are not currently linked with stored chapters in the local database. This should've happened automatically upon updating, but if it didn't complete, it can be re-executed this way."
                ) {
                    Task {
                        (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator(style: .progress)
                        await CoreDataManager.shared.migrateChapterHistory { progress in
                            Task { @MainActor in
                                (UIApplication.shared.delegate as? AppDelegate)?.indicatorProgress = progress
                            }
                        }
                        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
                        await (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()
                    }
                }
            case "Advanced.resetSettings":
                confirmAction(
                    title: NSLocalizedString("RESET_SETTINGS"),
                    message: NSLocalizedString("RESET_SETTINGS_TEXT")
                ) {
                    self.resetSettings()
                }
            case "Advanced.reset":
                confirmAction(
                    title: NSLocalizedString("RESET"),
                    message: NSLocalizedString("RESET_TEXT")
                ) {
                    (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()
                    clearNetworkCache()
                    resetSettings()
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearLibrary(context: context)
                            CoreDataManager.shared.clearManga(context: context)
                            CoreDataManager.shared.clearHistory(context: context)
                            CoreDataManager.shared.clearChapters(context: context)
                            CoreDataManager.shared.clearCategories(context: context)
                            CoreDataManager.shared.clearTracks(context: context)
                            try? context.save()
                        }
                        SourceManager.shared.clearSources()
                        SourceManager.shared.clearSourceLists()
                        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("updateTrackers"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
                        await (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()
                    }
                }
            default:
                break
        }
    }

    @ViewBuilder
    func pageContentHandler(_ key: String) -> (some View)? {
        if key == "Library.categories" {
            CategoriesView()
        } else if key == "PlayerLibrary.categories" {
            PlayerCategoriesView()
        } else if key == "Reader.tapZones" {
            TapZonesSelectView()
        } else if key == "Reader.upscalingModels" {
            UpscaleModelListView()
        } else if key == "Tracking" {
            SettingsTrackingView()
        } else if key == "About" {
            SettingsAboutView()
        } else if key == "Insights" {
            InsightsView()
        } else if key == "SourceLists" {
            SourceListsView()
        } else if key == "PlayerSources" {
            ModulesView()
        } else if key == "Downloads" {
            DownloadsView().environmentObject(path)
        } else if key == "History" {
            HistoryView().environmentObject(path)
        } else if key == "PlayerHistory" {
            HistoryView(initialKind: .player).environmentObject(path)
        }
    }

    @ViewBuilder
    func customContentHandler(_ setting: Setting) -> some View {
        if setting.key == "Library.defaultCategory" {
            let newSetting = {
                var setting = setting
                setting.value = .select(.init(
                    values: ["", "none"] + categories,
                    titles: [
                        NSLocalizedString("ALWAYS_ASK"), NSLocalizedString("NONE")
                    ] + categories
                ))
                return setting
            }()
            SettingView(setting: newSetting)
        } else if setting.key == "PlayerLibrary.defaultCategory" {
            let newSetting = {
                var setting = setting
                setting.value = .select(.init(
                    values: ["", "none"] + playerCategories,
                    titles: [
                        NSLocalizedString("ALWAYS_ASK"), NSLocalizedString("NONE")
                    ] + playerCategories
                ))
                return setting
            }()
            SettingView(setting: newSetting)
        } else if setting.key == "Library.lockedCategories" {
            let newSetting = {
                var setting = setting
                setting.value = .multiselect(.init(values: categories, authToOpen: true))
                return setting
            }()
            SettingView(setting: newSetting)
        } else if setting.key == "PlayerLibrary.lockedCategories" {
            let newSetting = {
                var setting = setting
                setting.value = .multiselect(.init(values: playerCategories, authToOpen: true))
                return setting
            }()
            SettingView(setting: newSetting)
        } else if setting.key == "PlayerLibrary.excludedUpdateCategories" {
            let newSetting = {
                var setting = setting
                setting.value = .multiselect(.init(values: playerCategories))
                return setting
            }()
            SettingView(setting: newSetting)
        } else if setting.key == "Library.excludedUpdateCategories" {
            let newSetting = {
                var setting = setting
                setting.value = .multiselect(.init(values: categories))
                return setting
            }()
            SettingView(setting: newSetting)
        }
    }
}

extension SettingsView {
    func confirmAction(
        title: String,
        message: String,
        continueActionName: String = NSLocalizedString("CONTINUE"),
        destructive: Bool = true,
        proceed: @escaping () -> Void
    ) {
        let alertView = UIAlertController(
            title: title,
            message: message,
            preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
        )

        let action = UIAlertAction(title: continueActionName, style: destructive ? .destructive : .default) { _ in proceed() }
        alertView.addAction(action)

        alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel))
        path.present(alertView, animated: true)
    }

    func clearNetworkCache() {
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            for record in records {
                WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {})
            }
        }
        // clear disk cache
        if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
            dataCache.removeAll()
        }
        // clear memory cache
        if let imageCache = ImagePipeline.shared.configuration.imageCache as? Nuke.ImageCache {
            imageCache.removeAll()
        }
    }

    func resetSettings() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
    }
}

// MARK: Searching
extension SettingsView {
    func search() {
        guard !searchText.isEmpty else {
            searchResult = nil
            return
        }
        var sections: [SettingSearchResult.Section] = []
        for rootSetting in Self.settings {
            guard case let .group(group) = rootSetting.value else { continue }

            var groupItems: [SettingPath] = []

            for setting in group.items {
                if case let .page(pageSetting) = setting.value {
                    let items = setting.search(for: searchText)
                    if !items.isEmpty {
                        sections.append(.init(icon: pageSetting.icon, header: setting.title, paths: items))
                    }
                } else {
                    if setting.title.contains(searchText) {
                        groupItems.append(.init(
                            key: setting.key,
                            title: setting.title,
                            paths: [setting.title],
                            setting: setting
                        ))
                    }
                }
            }

            if !groupItems.isEmpty {
                sections.append(.init(header: rootSetting.title.isEmpty ? nil : rootSetting.title, paths: groupItems))
            }
        }
        let result = SettingSearchResult(sections: sections)
        searchResult = result
    }

    func openSearchPage(for setting: SettingPath) {
        func findTargetPage(title: String) -> (Setting, PageSetting)? {
            for setting in Self.settings {
                if case let .group(group) = setting.value {
                    for item in group.items {
                        if case let .page(page) = item.value {
                            if item.title == title {
                                return (item, page)
                            }
                        }
                    }
                }
            }
            return nil
        }
        func findTargetSetting(title: String, in settings: [Setting]) -> Setting? {
            for setting in settings {
                if case let .group(group) = setting.value {
                    let result = findTargetSetting(title: title, in: group.items)
                    if let result {
                        return result
                    }
                } else if setting.title == title {
                    return setting
                }
            }
            return nil
        }
        guard
            let targetPageTitle = setting.paths.first,
            let (targetPageSetting, targetPage) = findTargetPage(title: targetPageTitle)
        else {
            return
        }
        let targetSetting = setting.paths[safe: 1].flatMap { targetSettingTitle in
            findTargetSetting(title: targetSettingTitle, in: targetPage.items)
        }

        let content = SettingPageDestination(
            setting: targetPageSetting,
            onChange: onSettingChange,
            value: targetPage,
            scrollTo: targetSetting
        )
        .settingPageContent(pageContentHandler)
        .settingCustomContent(customContentHandler)

        let controller = UIHostingController(rootView: content)
        let hasHeaderView = targetPage.icon != nil && targetPage.info != nil
        controller.title = hasHeaderView ? nil : targetPageSetting.title
        controller.navigationItem.largeTitleDisplayMode = .never
        path.push(controller)
    }
}

private extension Setting {
    func search(for text: String, currentPath: [String] = []) -> [SettingPath] {
        let path = currentPath + [title]

        func checkCurrent() -> [SettingPath] {
            if title.lowercased().contains(text.lowercased()) {
                return [.init(
                    key: key,
                    title: title,
                    paths: path,
                    setting: self
                )]
            }
            return []
        }

        switch value {
            case let .page(page):
                var results: [SettingPath] = checkCurrent()
                for item in page.items {
                    results.append(contentsOf: item.search(for: text, currentPath: path))
                }
                return results
            case let .group(group):
                var results: [SettingPath] = []
                for item in group.items {
                    results.append(contentsOf: item.search(for: text, currentPath: currentPath))
                }
                return results
            case .custom:
                // skip searching custom views
                return []
            default:
                return checkCurrent()
        }
    }
}
