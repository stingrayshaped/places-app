//
//  PlacesApp.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//

import SwiftUI
import SwiftData

@main
struct PlacesApp: App {
    var body: some Scene {
        WindowGroup {
            RestaurantListView()
                .onOpenURL { url in
                    ImportCenter.shared.load(url)
                }
        }
        .modelContainer(for: [Restaurant.self, TagDefinition.self])
    }
}
