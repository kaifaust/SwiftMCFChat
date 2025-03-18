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
        // IMPORTANT: For this app to work correctly, the following Info.plist entries
        // must be added through Xcode's target settings:
        //
        // 1. NSLocalNetworkUsageDescription (Privacy - Local Network Usage Description)
        //    A message explaining why you need local network access, e.g.,
        //    "MultiPeerDemo needs to access your local network to discover and connect to nearby devices."
        //
        // 2. NSBonjourServices with values:
        //    - _multipdemo-chat._tcp
        //    - _multipdemo-chat._udp
        //
        // To add these to your Xcode project:
        // 1. Select your target in Xcode
        // 2. Go to "Info" tab
        // 3. Add the above keys under "Custom iOS Target Properties"
        //
        // The app also needs network entitlements (already added to the entitlements file):
        // - com.apple.security.network.client
        // - com.apple.security.network.server

        print("🚀 Starting MultipeerDemo app...")
        print("📝 Device information:")
        #if canImport(UIKit)
        print("📱 Running on iOS device")
        #else
        print("💻 Running on macOS device")
        #endif
        
        print("📡 Service type: multipdemo-chat")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
