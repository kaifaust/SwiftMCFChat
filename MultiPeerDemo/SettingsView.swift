//
//  SettingsView.swift
//  MultiPeerDemo
//
//  Created by Claude on 3/22/25.
//

import SwiftUI
import MultipeerConnectivity

#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject var multipeerService: MultipeerService
    @Binding var isPresented: Bool
    @Binding var isSyncEnabled: Bool
    @Binding var currentInvitationPeer: MultipeerService.PeerInfo?
    @Binding var showConnectionRequestAlert: Bool
    @State private var selectedPeer: MultipeerService.PeerInfo?
    @State private var showForgetConfirmation = false
    
    // Helper computed properties
    
    private var deviceType: String {
        #if os(macOS)
        return "Mac"
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        return "device"
        #endif
    }
    
    private var deviceName: String {
        multipeerService.myPeerId.displayName
    }
    
    // Helper methods to simplify complex expressions for Swift type-checking
    private func getMyDevicesPeers() -> [MultipeerService.PeerInfo] {
        return multipeerService.discoveredPeers.filter { peer in
            // Include connected peers
            if peer.state == MultipeerService.PeerState.connected {
                return true
            }
            
            // Include disconnected peers (previously connected)
            if peer.state == MultipeerService.PeerState.disconnected {
                return true
            }
            
            // Get the userId if available
            let userId = peer.discoveryInfo?["userId"]
            
            // Check if this is a known peer with sync enabled
            let isKnownSyncEnabled = userId != nil && 
                                    multipeerService.isSyncEnabled(for: userId!)
            
            // Don't include rejected peers regardless of other conditions
            if peer.state == MultipeerService.PeerState.rejected {
                return false
            }
            
            // Include all connection state peers (discovered, connecting, invitationSent)
            // that are known and have sync enabled
            if isKnownSyncEnabled {
                return true
            }
            
            return false
        }
    }
    
    private func getOtherDevicesPeers() -> [MultipeerService.PeerInfo] {
        return multipeerService.discoveredPeers.filter { peer in
            // Exclude connected peers (already in My Devices)
            if peer.state == MultipeerService.PeerState.connected {
                return false
            }
            
            // Exclude disconnected peers (already in My Devices)
            if peer.state == MultipeerService.PeerState.disconnected {
                return false
            }
            
            // Get the userId if available
            let userId = peer.discoveryInfo?["userId"]
            
            // Check if this is a known peer with sync enabled
            let isKnownSyncEnabled = userId != nil && 
                                   multipeerService.isSyncEnabled(for: userId!)
            
            // Exclude ALL known sync-enabled peers (they go in My Devices)
            // except for rejected ones
            if isKnownSyncEnabled && peer.state != MultipeerService.PeerState.rejected {
                return false
            }
            
            // Include all other non-connected peers:
            // - All peers without sync enabled in any state
            // - Rejected peers (even if they were known/sync enabled)
            return true
        }
    }
    
    var body: some View {
        #if os(macOS)
        contentView
            .frame(minWidth: 500, minHeight: 600)
            .padding()
        #else
        NavigationView {
            contentView
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                    }
                }
        }
        #endif
    }
    
    private var contentView: some View {
        List {
            // Top section: Sync Devices with toggle
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync Devices")
                        .font(.headline)
                    
                    Text("Connect with your other devices such as Mac, iPhone, or iPad to automatically sync your chat history via peer-to-peer networking that doesn't require an internet connection.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                
                Toggle("Sync Devices", isOn: $isSyncEnabled)
                    .onChange(of: isSyncEnabled) { oldValue, newValue in
                        if newValue {
                            multipeerService.startHosting()
                            multipeerService.startBrowsing()
                        } else {
                            multipeerService.disconnect()
                        }
                    }
            } footer: {
                Text("This \(deviceType) is discoverable as \"\(deviceName)\" while Sync Devices is enabled.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            // My Devices section
            Section(header: Text("MY DEVICES").font(.footnote).foregroundColor(.secondary)) {
                let myDevicesPeers = getMyDevicesPeers()
                
                if !myDevicesPeers.isEmpty {
                    ForEach(myDevicesPeers) { peer in
                        deviceRowView(for: peer)
                    }
                } else {
                    Text("No devices")
                        .foregroundColor(.secondary)
                        .italic()
                        .font(.subheadline)
                }
            }
            
            // Other Devices section
            Section(header: Text("OTHER DEVICES").font(.footnote).foregroundColor(.secondary)) {
                let otherDevicesPeers = getOtherDevicesPeers()
                
                if !otherDevicesPeers.isEmpty {
                    ForEach(otherDevicesPeers) { peer in
                        deviceRowView(for: peer)
                    }
                } else {
                    Text("No devices")
                        .foregroundColor(.secondary)
                        .italic()
                        .font(.subheadline)
                }
            }
        }
        #if os(iOS)
        .listStyle(InsetGroupedListStyle())
        #else
        .listStyle(.inset)
        #endif
        #if os(macOS)
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                
                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top])
        }
        #endif
        // Forget device alert
        .alert("Forget Device", isPresented: $showForgetConfirmation) {
            Button("Cancel", role: .cancel) { }
            
            Button("Forget", role: .destructive) {
                if let peer = selectedPeer, let userId = peer.discoveryInfo?["userId"] {
                    multipeerService.forgetDevice(userId: userId)
                }
                selectedPeer = nil
            }
        } message: {
            if let peer = selectedPeer {
                Text("Do you want to forget device \(peer.peerId.displayName)? This will remove it from known peers.")
            } else {
                Text("Do you want to forget this device?")
            }
        }
        // Connection request alert for settings view
        .alert("Connection Request", isPresented: $showConnectionRequestAlert) {
            Button("Accept") {
                if let peer = currentInvitationPeer {
                    multipeerService.acceptInvitation(from: peer, accept: true)
                }
                currentInvitationPeer = nil
            }
            Button("Decline", role: .cancel) {
                if let peer = currentInvitationPeer {
                    multipeerService.acceptInvitation(from: peer, accept: false)
                }
                currentInvitationPeer = nil
            }
        } message: {
            if let peer = currentInvitationPeer {
                Text("\(peer.peerId.displayName) wants to connect. Do you want to accept?")
            } else {
                Text("A device wants to connect. Do you want to accept?")
            }
        }
    }
    
    // Helper view to create consistent device rows in the list
    @ViewBuilder
    private func deviceRowView(for peer: MultipeerService.PeerInfo) -> some View {
        HStack {
            // Device name and status
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.peerId.displayName)
                    .font(.system(size: 16))
                Text(statusText(for: peer))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action button based on peer state
            actionButton(for: peer)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isActionable(peer.state) {
                handlePeerAction(peer)
            }
        }
        .contextMenu {
            if peer.discoveryInfo?["userId"] != nil {
                Button(action: {
                    selectedPeer = peer
                    showForgetConfirmation = true
                }) {
                    Label("Forget Device", systemImage: "trash")
                }
                
                Button(action: {
                    if let userId = peer.discoveryInfo?["userId"] {
                        multipeerService.blockUser(userId: userId)
                    }
                }) {
                    Label("Block Device", systemImage: "nosign")
                }
            }
        }
    }
    
    // Helper method to get status color for peer
    private func statusColor(for peer: MultipeerService.PeerInfo) -> Color {
        switch peer.state {
        case .connected:
            return .green
        case .connecting, .invitationSent:
            return .orange
        case .disconnected:
            return peer.isNearby ? .yellow : .gray
        case .discovered:
            return .blue
        case .rejected:
            return .red
        default:
            return .gray
        }
    }
    
    // Helper method to get status text for peer
    private func statusText(for peer: MultipeerService.PeerInfo) -> String {
        switch peer.state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .invitationSent:
            return "Invitation Sent"
        case .disconnected:
            return peer.isNearby ? "Not Connected, Nearby" : "Not Connected"
        case .discovered:
            return "Available"
        case .rejected:
            return "Invitation Declined"
        default:
            return "Unknown"
        }
    }
    
    // Helper method to create the appropriate action button for the peer
    @ViewBuilder
    private func actionButton(for peer: MultipeerService.PeerInfo) -> some View {
        if isActionable(peer.state) {
            Button(action: {
                handlePeerAction(peer)
            }) {
                Text(actionButtonText(for: peer))
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        } else if peer.state == .connected {
            // For connected peers, show a "Connected" indicator
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else if peer.state == .invitationSent {
            // For peers with sent invitations, show a spinner or waiting indicator
            Image(systemName: "hourglass")
                .foregroundColor(.orange)
        } else {
            EmptyView()
        }
    }
    
    // Helper method to get button text based on peer state
    private func actionButtonText(for peer: MultipeerService.PeerInfo) -> String {
        switch peer.state {
        case .discovered:
            return "Connect"
        case .disconnected:
            return peer.isNearby ? "Reconnect" : "Connect"
        case .rejected:
            return "Try Again"
        default:
            return ""
        }
    }
    
    // Determine if peer state is actionable (can be tapped to connect)
    private func isActionable(_ state: MultipeerService.PeerState) -> Bool {
        // Discovered, disconnected and rejected peers can be tapped to connect/retry
        return state == .discovered || state == .rejected || state == .disconnected
    }
    
    // Handle peer action based on its current state
    private func handlePeerAction(_ peer: MultipeerService.PeerInfo) {
        if peer.state == .discovered || peer.state == .rejected || peer.state == .disconnected {
            // Invite peer (or retry invitation for rejected/disconnected peers)
            print("👆 User tapped \(peer.peerId.displayName) with state \(peer.state.rawValue)")
            multipeerService.invitePeer(peer)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var isPresented = true
        @State var isSyncEnabled = true
        @State var currentPeer: MultipeerService.PeerInfo? = nil
        @State var showAlert = false
        
        var body: some View {
            SettingsView(
                isPresented: $isPresented,
                isSyncEnabled: $isSyncEnabled,
                currentInvitationPeer: $currentPeer,
                showConnectionRequestAlert: $showAlert
            )
            .environmentObject(MultipeerService())
        }
    }
    
    return PreviewWrapper()
}