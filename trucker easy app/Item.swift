//
//  Item.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
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
