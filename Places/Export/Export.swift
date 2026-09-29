//
//  Export.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//

import Foundation

struct RestaurantDTO: Codable {
    var id: UUID
    var name: String
    var address: String
    var review: String
    var createdAt: Date
    var updatedAt: Date
}

struct ExportFile: Codable {
    var version = 1
    var exportedAt = Date()
    var restaurants: [RestaurantDTO]
}
