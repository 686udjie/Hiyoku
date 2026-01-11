//
//  PlayerHistoryView.swift
//  Hiyoku
//
//  Created by 686udjie on 1/10/26.
//

import SwiftUI

struct PlayerHistoryView: View {
    @StateObject private var viewModel = ViewModel()
    @State private var showingClearAlert = false

    var body: some View {
        NavigationView {
            Group {
                if viewModel.historyItems.isEmpty && !viewModel.isLoading {
                    emptyStateView
                } else {
                    historyListView
                }
            }
            .navigationTitle("Player History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.historyItems.isEmpty {
                        Button("Clear") {
                            showingClearAlert = true
                        }
                    }
                }
            }
            .alert("Clear History", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    Task {
                        await viewModel.clearAllHistory()
                    }
                }
            } message: {
                Text("This will remove all player viewing history. This action cannot be undone.")
            }
            .task {
                await viewModel.loadHistory()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Player History")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text("Your watched player episodes will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyListView: some View {
        List {
            ForEach(viewModel.historyItems) { item in
                PlayerHistoryRowView(item: item)
            }
            .onDelete { indexSet in
                Task {
                    await viewModel.removeHistory(at: indexSet)
                }
            }
        }
        .refreshable {
            await viewModel.loadHistory()
        }
    }
}

struct PlayerHistoryRowView: View {
    let item: PlayerHistoryItem

    var body: some View {
        HStack(spacing: 12) {
            // Episode info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.playerTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("Episode \(item.episodeNumber)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let episodeTitle = item.episodeTitle, !episodeTitle.isEmpty {
                    Text(episodeTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Progress and date
            VStack(alignment: .trailing, spacing: 4) {
                // Progress bar
                ProgressView(value: item.progressPercentage)
                    .frame(width: 60)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))

                Text("\(Int(item.progressPercentage * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(item.dateWatched, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - ViewModel

extension PlayerHistoryView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var historyItems: [PlayerHistoryItem] = []
        @Published var isLoading = false

        func loadHistory() async {
            withAnimation {
                isLoading = true
            }
            let items = await PlayerHistoryManager.shared.getAllHistory()
            withAnimation {
                historyItems = items
                isLoading = false
            }
        }

        func removeHistory(at indexSet: IndexSet) async {
            let itemsToRemove: [PlayerHistoryItem] = indexSet.compactMap { index in
                guard index < historyItems.count else { return nil }
                return historyItems[index]
            }
            withAnimation {
                historyItems.remove(atOffsets: indexSet)
            }
            for item in itemsToRemove {
                await PlayerHistoryManager.shared.removeHistory(
                    episodeId: item.episodeId,
                    moduleId: item.moduleId
                )
            }
            await loadHistory()
        }

        func clearAllHistory() async {
            // This would need to be implemented in PlayerHistoryManager
            // For now, we'll remove items one by one
            let itemsToRemove = historyItems
            withAnimation {
                historyItems = []
            }
            for item in itemsToRemove {
                await PlayerHistoryManager.shared.removeHistory(
                    episodeId: item.episodeId,
                    moduleId: item.moduleId
                )
            }
            await loadHistory()
        }
    }
}

#Preview {
    PlayerHistoryView()
}
