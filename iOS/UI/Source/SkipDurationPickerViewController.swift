//
//  SkipDurationPickerViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit

class SkipDurationPickerViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    var selectedDuration: Int = 85

    private let pickerView = UIPickerView()
    private let values = Array(1...255)

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        preferredContentSize = CGSize(width: 270, height: 160)
        pickerView.dataSource = self
        pickerView.delegate = self
        if let index = values.firstIndex(of: selectedDuration) {
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
        values.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        "\(values[row])s"
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        selectedDuration = values[row]
    }

    func getSelectedDuration() -> Int {
        selectedDuration
    }
}
