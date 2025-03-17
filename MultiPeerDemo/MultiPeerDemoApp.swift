//
//  MultiPeerDemoApp.swift
//  MultiPeerDemo
//
//  Created by Kai on 3/17/25.
//

import SwiftUI

@main
struct MultiPeerDemoApp: App {
    init() {
        // This is just a workaround to ensure the Info.plist entries are added
        // These should be added to the project settings for:
        // - NSLocalNetworkUsageDescription
        // - NSBonjourServices (_mpd-messages._tcp, _mpd-messages._udp)
        print("Starting MultipeerDemo app...")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
