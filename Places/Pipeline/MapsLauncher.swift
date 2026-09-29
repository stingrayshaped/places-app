//
//  TravelMode.swift
//  Places
//
//  Created by Raymond Yang on 9/29/26.
//


import MapKit
import CoreLocation
import UIKit

enum TravelMode {
    case driving, walking, transit

    var launchValue: String {
        switch self {
        case .driving: MKLaunchOptionsDirectionsModeDriving
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .transit: MKLaunchOptionsDirectionsModeTransit
        }
    }

    /// Value for the Apple Maps URL's dirflg parameter.
    var urlFlag: String {
        switch self {
        case .driving: "d"
        case .walking: "w"
        case .transit: "r"
        }
    }
}

enum MapsLauncher {
    /// Opens Apple Maps with directions to the restaurant.
    @MainActor
    static func openDirections(to restaurant: Restaurant, mode: TravelMode) {
        if restaurant.hasVerifiedLocation,
           let latitude = restaurant.latitude,
           let longitude = restaurant.longitude {
            // Exact spot, labeled with the restaurant's name.
            let item = MKMapItem(
                location: CLLocation(latitude: latitude, longitude: longitude),
                address: MKAddress(fullAddress: restaurant.address, shortAddress: nil)
            )
            item.name = restaurant.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode.launchValue])
        } else {
            // No verified match: let Maps look up the address text.
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: restaurant.address),
                URLQueryItem(name: "dirflg", value: mode.urlFlag)
            ]
            if let url = components?.url {
                UIApplication.shared.open(url)
            }
        }
    }
}