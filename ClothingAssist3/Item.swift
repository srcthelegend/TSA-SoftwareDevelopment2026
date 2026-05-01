//
//  Item.swift
//  ClothingAssist3
//
//  Created by Anish Talla on 5/1/26.
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
