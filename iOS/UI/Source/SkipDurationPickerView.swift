//
//  SkipDurationPickerView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/23/26.
//

import UIKit

class SkipDurationPickerViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    private let pickerView = UIPickerView()
    private let durations = Array(stride(from: 0, through: 300, by: 1))
    var selectedDuration: Double = 85
    override func viewDidLoad() {
        super.viewDidLoad()
        pickerView.dataSource = self
        pickerView.delegate = self
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pickerView)
        NSLayoutConstraint.activate([
            pickerView.topAnchor.constraint(equalTo: view.topAnchor),
            pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pickerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if let index = durations.firstIndex(of: Int(selectedDuration)) {
            pickerView.selectRow(index, inComponent: 0, animated: false)
        }
        let height: CGFloat = 200
        preferredContentSize = CGSize(width: 270, height: height)
    }
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        durations.count
    }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        "\(durations[row])s"
    }
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        selectedDuration = Double(durations[row])
    }
    func getSelectedDuration() -> Double {
        selectedDuration
    }
}
