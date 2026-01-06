//
//  PlayerViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 5/1/26.
//

import UIKit

class PlayerViewController: BaseViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("PLAYER")

        // Placeholder for player
        let label = UILabel()
        label.text = "Player functionality coming soon"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
