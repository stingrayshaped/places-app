//
//  StarterTag.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//


import SwiftData
import Foundation

struct StarterTag {
    let key: String
    let name: String
    let kind: TagKind
    let section: String
    let definition: String
}

enum StarterVocabulary {

    static let text = """
    # Cuisine
    American
    BBQ
    Brazilian
    Caribbean
    Chinese
    Ethiopian
    French
    Greek
    Indian
    Italian
    Japanese
    Korean
    Mediterranean
    Mexican
    Middle Eastern
    Peruvian
    Southern
    Spanish
    Thai
    Vietnamese

    # Type
    Bakery
    Bar / Pub
    Burgers
    Coffee Shop
    Dessert
    Deli / Sandwiches
    Diner
    Fast Casual
    Fine Dining
    Food Truck
    Pizza
    Ramen
    Seafood
    Steakhouse
    Sushi
    Tacos

    # Timing
    Open Early | Opens by about 7 am
    Open Late | Open past about 10 pm
    Open 24 Hours | Open around the clock
    Serves Breakfast | Serves breakfast items
    Serves Brunch | Serves brunch, usually on weekends

    # Getting a Table
    Takes Reservations | Accepts reservations
    Walk-Ins Welcome | Easy to get a table without booking

    # Group Fit
    Good for Large Groups | Handles parties of about six or more
    Good for Solo Diners | Comfortable for eating alone
    Kid Friendly | Welcoming to children
    Private Room / Event Space | Has a private room or space for events
    Family Style / Shared Plates | Food is meant to be shared
    Separate Checks OK | Will split the bill

    # Seating & Space
    Outdoor Seating | Has a patio or outdoor tables
    Bar Seating | Seats at the bar
    Quiet | Easy to hold a conversation
    Dog Friendly | Dogs are welcome

    # Service Style
    Counter Service | Order at the counter
    Takeout | Offers takeout
    Delivery | Offers delivery
    Drive-Thru | Has a drive-thru
    Curbside Pickup | Offers curbside pickup

    # Drinks
    Full Bar | Serves cocktails and spirits
    Beer & Wine Only | Serves beer and wine but no spirits
    BYOB | Bring your own alcohol

    # Getting There
    Parking Available | Has parking or easy parking nearby
    Valet | Offers valet parking
    Transit Accessible | Easy to reach by public transit
    Wheelchair Accessible | Accessible to wheelchair users

    # Dietary
    Vegetarian Options | Has vegetarian dishes
    Vegan Options | Has vegan dishes
    Gluten-Free Options | Has gluten-free dishes
    Halal | Serves halal food
    Kosher | Serves kosher food

    # Price
    $ | Under about $15 a person
    $$ | About $15 to $30 a person
    $$$ | About $30 to $60 a person
    $$$$ | Over about $60 a person

    ! Warnings
    Cash Only | Does not take cards
    Reservations Required | Hard to get a table without booking
    Long Waits | Expect a line or a wait at peak times
    No Parking | Parking is unavailable or hard to find
    Limited Seating | Very small, with few tables
    Auto-Gratuity | A service charge is added automatically
    Closes Early | Closes earlier than most places
    Not Wheelchair Accessible | Not accessible to wheelchair users
    Loud | Hard to hold a conversation
    """

    static func parse() -> [StarterTag] {
        var result: [StarterTag] = []
        var section = "Other"
        var kind: TagKind = .tag

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                section = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                kind = .tag
                continue
            }
            if line.hasPrefix("!") {
                section = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                kind = .warning
                continue
            }

            let parts = line
                .split(separator: "|", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = parts.first, !name.isEmpty else { continue }

            result.append(StarterTag(
                key: TagRules.slug(name),
                name: name,
                kind: kind,
                section: section,
                definition: parts.count > 1 ? parts[1] : ""
            ))
        }
        return result
    }
}

enum VocabularySeeder {
    /// Fills the vocabulary the first time the app runs.
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<TagDefinition>())) ?? 0
        guard count == 0 else { return }

        for (index, starter) in StarterVocabulary.parse().enumerated() {
            context.insert(TagDefinition(
                key: starter.key,
                name: starter.name,
                kind: starter.kind,
                section: starter.section,
                definition: starter.definition,
                sortOrder: index
            ))
        }
        try? context.save()
    }
}