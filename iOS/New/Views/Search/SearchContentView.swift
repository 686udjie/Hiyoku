//
//  SearchContentView.swift
//  Aidoku
//
//  Created by Skitty on 11/14/25.
//

import AidokuRunner
import SwiftUI
import NukeUI

struct SearchContentView: View {
    @StateObject private var viewModel: ViewModel
    @Binding private var searchText: String
    @Binding var searchCommitToggle: Bool
    @Binding private var filters: [FilterValue]
    let openResult: (ViewModel.SearchResult) -> Void
    let dismissKeyboard: () -> Void
    let path: NavigationCoordinator

    @State private var keyboardOffset: CGFloat = 0
    @Namespace private var animation

    init(
        viewModel: ViewModel,
        searchText: Binding<String>,
        searchCommitToggle: Binding<Bool> = .constant(false),
        filters: Binding<[FilterValue]>,
        openResult: @escaping (ViewModel.SearchResult) -> Void,
        dismissKeyboard: @escaping () -> Void,
        path: NavigationCoordinator
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self._searchText = searchText
        self._searchCommitToggle = searchCommitToggle
        self._filters = filters
        self.openResult = openResult
        self.dismissKeyboard = dismissKeyboard
        self.path = path
    }

    var body: some View {
        Group {
            if searchText.isEmpty && viewModel.history.isEmpty {
                UnavailableView(
                    NSLocalizedString("NO_RECENT_SEARCHES"),
                    systemImage: "magnifyingglass",
                    description: Text(NSLocalizedString("NO_RECENT_SEARCHES_TEXT"))
                )
                .offset(y: -keyboardOffset / 2)
                .ignoresSafeArea(.all)
            } else if !searchText.isEmpty && viewModel.resultsIsEmpty {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .ignoresSafeArea()
                } else {
                    UnavailableView.search(text: searchText)
                        .ignoresSafeArea()
                }
            } else {
                List {
                    if searchText.isEmpty {
                        if !viewModel.history.isEmpty {
                            historyItems
                        }
                    } else {
                        searchResults
                    }
                }
                .scrollBackgroundHiddenPlease()
                .scrollDismissesKeyboardImmediately()
                .listStyle(.grouped)
                .environment(\.defaultMinListRowHeight, 10)
            }
        }
        .detectKeyboardOffset($keyboardOffset)
        .animation(.default, value: viewModel.results)
        .navigationTitle(NSLocalizedString("SEARCH"))
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                viewModel.results = []
            }
            viewModel.search(query: newValue, delay: true)
        }
        .onChange(of: searchCommitToggle) { _ in
            viewModel.search(query: searchText, delay: false)
        }
        .onChange(of: filters) { newValue in
            viewModel.updateFilters(newValue)
        }
    }

    var historyItems: some View {
        Section {
            ForEach(viewModel.history.reversed(), id: \.self) { item in
                VStack(spacing: 0) {
                    Button {
                        searchText = item
                        dismissKeyboard()
                        viewModel.search(query: item, delay: false)
                    } label: {
                        HStack {
                            let imageName = if #available(iOS 18.0, *) {
                                "clock.arrow.trianglehead.counterclockwise.rotate.90"
                            } else {
                                "clock.arrow.circlepath"
                            }
                            Image(systemName: imageName)
                                .foregroundStyle(.tint)
                                .imageScale(.small)
                            Text(item)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(ListButtonStyle(tint: false))

                    Divider().padding(.horizontal)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.removeHistory(item: item)
                    } label: {
                        Label(NSLocalizedString("DELETE"), systemImage: "trash")
                    }
                }
                .foregroundStyle(.primary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(.zero)
            }
        } header: {
            HStack {
                Text(NSLocalizedString("RECENTLY_SEARCHED"))
                Spacer()
                Button(NSLocalizedString("CLEAR")) {
                    viewModel.clearHistory()
                }
            }
            .font(.body)
            .textCase(nil)
        }
    }

    private func mangaSourceSection(
        for searchResult: SearchContentView.ViewModel.SearchResult,
        result: AidokuRunner.MangaPageResult,
        id: Int
    ) -> some View {
        Section {
            HomeScrollerView(
                source: searchResult.source!,
                component: .init(
                    title: nil,
                    value: .scroller(entries: result.entries.map { $0.intoLink() })
                )
            )
            .id("\(searchResult.source!.key).\(id)")
            .environmentObject(path)
            .listRowBackground(Color.clear)
            .listRowInsets(.zero)
            .listRowSeparator(.hidden)
        } header: {
            HStack {
                SourceIconView(
                    sourceId: searchResult.source!.key,
                    imageUrl: searchResult.source!.imageUrl,
                    iconSize: 29
                )
                .scaleEffect(0.75)
                Text(searchResult.source!.name)

                Spacer()

                Button(NSLocalizedString("VIEW_MORE")) {
                    openResult(searchResult)
                }
            }
            .font(.body)
            .textCase(nil)
        }
    }

    private func playerModuleSection(for searchResult: SearchContentView.ViewModel.SearchResult, result: AidokuRunner.MangaPageResult) -> some View {
        _ = {
            var hasher = Hasher()
            for entry in result.entries {
                hasher.combine(entry)
            }
            return hasher.finalize()
        }()

        return Section {
            // Reimplement banner card display for player (similar to HomeScrollerView)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(0..<min(result.entries.count, 5), id: \.self) { index in
                        let entry = result.entries[index]
                        Button {
                            openResult(searchResult)
                        } label: {
                            VStack(alignment: .leading) {
                                // Cover image (similar to individual player sources)
                                LazyImage(url: URL(string: entry.cover ?? "")) { state in
                                    if let uiImage = state.imageContainer?.image {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 120, height: 180)
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                    } else {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 120, height: 180)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundStyle(.gray)
                                            )
                                    }
                                }

                                // Title
                                Text(entry.title)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 120, alignment: .leading)
                                    .padding(.top, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .frame(height: 220) // Fixed height for horizontal scrolling
        } header: {
            HStack {
                if !searchResult.module!.metadata.iconUrl.isEmpty {
                    AsyncImage(url: URL(string: searchResult.module!.metadata.iconUrl)) { image in
                        image
                            .resizable()
                            .frame(width: 29, height: 29)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 29, height: 29)
                    }
                }
                Text(searchResult.module!.metadata.sourceName)

                Spacer()

                Button(NSLocalizedString("VIEW_MORE")) {
                    openResult(searchResult)
                }
            }
            .font(.body)
            .textCase(nil)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(.zero)
        .listRowSeparator(.hidden)
    }

    var searchResults: some View {
        Group {
            ForEach(Array(viewModel.results), id: \.id) { searchResult in
                let result = searchResult.result

                if !result.entries.isEmpty {
                    if searchResult.source != nil {
                        mangaSourceSection(for: searchResult, result: result, id: {
                            var hasher = Hasher()
                            for entry in result.entries {
                                hasher.combine(entry)
                            }
                            return hasher.finalize()
                        }())
                    } else if searchResult.module != nil {
                        playerModuleSection(for: searchResult, result: result)
                    }
                }
            }
        }
    }
}
