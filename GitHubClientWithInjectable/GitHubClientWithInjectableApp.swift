//
//  GitHubClientWithInjectableApp.swift
//  GitHubClientWithInjectable
//
//  Created by Franco Bellu on 17/1/23.
//

import SwiftUI

@main
struct GitHubClientWithInjectableApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
//                .injectedValue(\.gitHub, value: .mock())
        }
    }
}
