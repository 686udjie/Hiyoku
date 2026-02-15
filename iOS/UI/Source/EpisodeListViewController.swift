//
//  EpisodeListViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit

class EpisodeListViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    var episodes: [PlayerEpisode] = []
    var currentEpisode: PlayerEpisode?
    var onSelect: ((PlayerEpisode) -> Void)?

    private let pickerView = UIPickerView()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        preferredContentSize = CGSize(width: 270, height: 160)
        pickerView.dataSource = self
        pickerView.delegate = self

        if let current = currentEpisode, let index = episodes.firstIndex(where: { $0.url == current.url }) {
            pickerView.selectRow(index, inComponent: 0, animated: false)
        }

        view.addSubview(pickerView)
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pickerView.topAnchor.constraint(equalTo: view.topAnchor),
            pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pickerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        episodes.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        let episode = episodes[row]
        let prefix = "Episode \(episode.number)"
        if episode.title.isEmpty || episode.title == prefix || episode.title == "Episode \(episode.number)" {
            return prefix
        }
        return "\(prefix): \(episode.title)"
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        // revamp
    }

    func getSelectedEpisode() -> PlayerEpisode? {
        let row = pickerView.selectedRow(inComponent: 0)
        guard row >= 0 && row < episodes.count else { return nil }
        return episodes[row]
    }
}
