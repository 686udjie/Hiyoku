//
//  PlayerInfoViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import UIKit
import SwiftUI

class PlayerInfoViewController: UIHostingController<PlayerInfoView> {
    let bookmark: PlayerLibraryItem?
    let searchItem: SearchItem?
    let module: ScrapingModule?
    let path: NavigationCoordinator

    init(
        bookmark: PlayerLibraryItem? = nil,
        searchItem: SearchItem? = nil,
        module: ScrapingModule? = nil,
        path: NavigationCoordinator
    ) {
        self.bookmark = bookmark
        self.searchItem = searchItem
        self.module = module
        self.path = path

        super.init(rootView: PlayerInfoView(
            bookmark: bookmark,
            searchItem: searchItem,
            module: module,
            path: path
        ))

        // Set navigation properties immediately like MangaViewController does
        let title = bookmark?.title ?? searchItem?.title ?? "Unknown Player"
        navigationItem.title = title
        navigationItem.titleView = UIView() // hide navigation bar title
        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
