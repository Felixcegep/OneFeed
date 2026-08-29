//
//  Item.swift
//  MonoRss
//
//  Created by Felix Lachapelle on 2026-08-29.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
