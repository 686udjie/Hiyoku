//
//  SearchItem.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import Foundation

struct SearchItem: Identifiable {
    let id = UUID()
    let title: String
    let imageUrl: String
    let href: String
}
