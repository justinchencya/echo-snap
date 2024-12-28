//
//  EchoSnapApp.swift
//  EchoSnap
//
//  Created by Justin Chen on 12/27/24.
//

import SwiftUI

@main
struct EchoSnapApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
