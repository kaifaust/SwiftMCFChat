//
//  ContentView.swift
//  MultiPeerDemo
//
//  Created by Kai on 3/17/25.
//

import SwiftUI
import MultipeerConnectivity

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject var multipeerService: MultipeerService
    @State private var messageText = ""
    @State private var isSyncEnabled = true
    @State private var showInfoAlert = false
    @State private var showSyncConflictAlert = false
    @State private var showClearConfirmation = false
    @State private var showConnectionRequestAlert = false
    @State private var currentInvitationPeer: MultipeerService.PeerInfo?
    @State private var showPeerContextMenu = false
    @State private var selectedPeer: MultipeerService.PeerInfo?
    @State private var showForgetConfirmation = false
    @State private var showSettings = false // Added state for settings sheet
    
    // Specifically for handling connection requests in settings view
    @State private var settingsShowConnectionAlert = false
    
    var body: some View {
        VStack {
            // Simplified header
            HStack {
                Text("MultipeerDemo")
                    .font(.headline)
                
                Spacer()
                
                // Clear history button
                Button(action: {
                    showClearConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 22))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 4)
                
                // Settings button
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
            }
            .padding()
            
            // Clear history confirmation alert
            .alert("Clear Chat History", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    multipeerService.clearAllMessages()
                }
            } message: {
                Text("Are you sure you want to clear all messages? This action cannot be undone.")
            }
            
            // Settings sheet
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    isPresented: $showSettings, 
                    isSyncEnabled: $isSyncEnabled,
                    currentInvitationPeer: $currentInvitationPeer,
                    showConnectionRequestAlert: $settingsShowConnectionAlert
                )
                .environmentObject(multipeerService)
            }
            
            // Message list with improved styling and autoscroll
            ScrollViewReader { scrollView in
                List {
                    ForEach(multipeerService.messages) { message in
                        HStack {
                            if message.isSystemMessage {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.gray)
                                
                                Text(message.content)
                                    .foregroundColor(.gray)
                                    .italic()
                                    .font(.footnote)
                            } else if message.senderId == multipeerService.userId {
                                // Messages from the current user (displayed on the right)
                                Text(message.content)
                                    .foregroundColor(.blue)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                // Messages from other devices with the same user ID (also displayed on the right)
                                // In our cloned chat implementation, all messages from the same user ID should be aligned the same way
                                Text(message.content)
                                    .foregroundColor(.blue)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .id(message.id)
                        .padding(.vertical, 2)
                    }
                    .onChange(of: multipeerService.messages.count) { oldCount, newCount in
                        if !multipeerService.messages.isEmpty {
                            withAnimation {
                                scrollView.scrollTo(multipeerService.messages.last?.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            
            // Sync conflict resolution alert
            .onChange(of: multipeerService.hasPendingSyncDecision) { oldValue, hasPending in
                showSyncConflictAlert = hasPending
            }
            .alert("Message History Conflict", isPresented: $showSyncConflictAlert) {
                Button("Use Remote History", role: .destructive) {
                    multipeerService.resolveMessageSyncConflict(useRemote: true)
                }
                
                Button("Keep Local History", role: .cancel) {
                    multipeerService.resolveMessageSyncConflict(useRemote: false)
                }
            } message: {
                if let peerID = multipeerService.pendingSyncPeer {
                    Text("There is a conflict between your message history and \(peerID.displayName)'s history. Which one would you like to keep?")
                } else {
                    Text("There is a conflict between message histories. Which one would you like to keep?")
                }
            }
            
            
            // Message input with improved UI
            HStack {
                TextField("Type a message", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(messageText.isEmpty || multipeerService.connectedPeers.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty || multipeerService.connectedPeers.isEmpty)
            }
            .padding()
        }
        // Update sync status when toggle changes in settings view
        .onChange(of: isSyncEnabled) { oldValue, newValue in
            if newValue {
                multipeerService.startHosting()
                multipeerService.startBrowsing()
            } else {
                multipeerService.disconnect()
            }
        }
        .onAppear {
            multipeerService.messages.append(MultipeerService.ChatMessage.systemMessage("Welcome to MultipeerDemo"))
            multipeerService.messages.append(MultipeerService.ChatMessage.systemMessage("Sync is enabled by default"))
            
            // Start sync automatically since it's enabled by default
            multipeerService.startHosting()
            multipeerService.startBrowsing()
            
            // Log our device categorization rules
            print("📋 Device categorization rules:")
            print("  - My Devices section includes:")
            print("    1. Connected peers (state == .connected)")
            print("    2. Disconnected peers - previously connected (state == .disconnected)")
            print("    3. Known peers with sync enabled in any state (including discovered, connecting, invitationSent)")
            print("    4. Rejected peers are excluded, even if known and sync enabled")
            print("  - Other Devices section includes:")
            print("    1. All peers that are not known or don't have sync enabled")
            print("    2. Rejected peers (even if they were known and sync enabled)")
            print("    3. Any peer not in the My Devices category")
            
            // Register for invitation handling
            multipeerService.pendingInvitationHandler = { peerID, invitationHandler in
                // Find or create a PeerInfo for this peer
                let peerInfo: MultipeerService.PeerInfo
                if let existing = multipeerService.discoveredPeers.first(where: { $0.peerId == peerID }) {
                    peerInfo = existing
                } else {
                    peerInfo = MultipeerService.PeerInfo(peerId: peerID, state: MultipeerService.PeerState.discovered)
                }
                
                // Set up the invitation peer so it's available to both views
                currentInvitationPeer = peerInfo
                
                // Show the connection request in the appropriate view
                if showSettings {
                    // If settings view is open, show the alert there
                    settingsShowConnectionAlert = true
                } else {
                    // Otherwise, show it in the main view
                    showConnectionRequestAlert = true
                }
            }
        }
        // Add universal connection request alert
        // On iOS, this is always shown in the main view
        // On macOS, this is only shown when the settings sheet is not open
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
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        // Send message directly without any platform-specific commands
        multipeerService.sendMessage(messageText)
        messageText = ""
    }
}

// View for displaying a single peer item
struct PeerItemView: View {
    let peer: MultipeerService.PeerInfo
    let action: () -> Void
    var onContextMenu: (() -> Void)? = nil
    @EnvironmentObject var multipeerService: MultipeerService
    
    var body: some View {
        VStack {
            // Peer icon based on state
            Image(systemName: iconForState(peer.state))
                .font(.system(size: 24))
                .foregroundColor(colorForState(peer.state))
                .frame(width: 40, height: 40)
                .background(colorForState(peer.state).opacity(0.2))
                .clipShape(Circle())
            
            // Peer name
            Text(peer.peerId.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            
            // Peer state with nearby status for disconnected peers
            if peer.state == MultipeerService.PeerState.disconnected {
                if peer.isNearby {
                    Text("Not Connected, Nearby")
                        .font(.caption2)
                        .foregroundColor(colorForState(peer.state))
                } else {
                    Text("Not Connected")
                        .font(.caption2)
                        .foregroundColor(Color.gray)
                }
            } else {
                Text(peer.state.rawValue)
                    .font(.caption2)
                    .foregroundColor(colorForState(peer.state))
            }
        }
        .frame(width: 90)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .opacity(isActionable(peer.state) ? 1.0 : 0.6)
        .onTapGesture {
            if isActionable(peer.state) {
                action()
            }
        }
        .contextMenu {
            if peer.state == MultipeerService.PeerState.connected || peer.state == MultipeerService.PeerState.discovered {
                // Check if peer has a userId (needed for the context menu actions)
                if peer.discoveryInfo?["userId"] != nil {
                    Button(action: {
                        if let onContextMenu = onContextMenu {
                            onContextMenu()
                        }
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
    }
    
    // Determine if peer state is actionable (can be tapped)
    private func isActionable(_ state: MultipeerService.PeerState) -> Bool {
        return state == MultipeerService.PeerState.discovered || 
               state == MultipeerService.PeerState.disconnected || 
               state == MultipeerService.PeerState.rejected
    }
    
    // Get appropriate icon for peer state
    private func iconForState(_ state: MultipeerService.PeerState) -> String {
        switch state {
        case MultipeerService.PeerState.discovered:
            return "person.crop.circle.badge.plus"
        case MultipeerService.PeerState.connecting:
            return "arrow.triangle.2.circlepath"
        case MultipeerService.PeerState.connected:
            return "checkmark.circle"
        case MultipeerService.PeerState.disconnected:
            // Use different icons based on whether peer is nearby or not
            return peer.isNearby ? "person.crop.circle.badge.clock" : "person.crop.circle.badge.xmark"
        case MultipeerService.PeerState.invitationSent:
            return "envelope"
        case MultipeerService.PeerState.rejected:
            return "xmark.circle"
        default:
            return "person.crop.circle.badge.questionmark"
        }
    }
    
    // Get appropriate color for peer state
    private func colorForState(_ state: MultipeerService.PeerState) -> Color {
        switch state {
        case MultipeerService.PeerState.discovered:
            return .blue
        case MultipeerService.PeerState.connecting:
            return .orange
        case MultipeerService.PeerState.connected:
            return .green
        case MultipeerService.PeerState.disconnected:
            // Use a more muted color for disconnected peers
            return .gray.opacity(0.8)
        case MultipeerService.PeerState.invitationSent:
            return .purple
        case MultipeerService.PeerState.rejected:
            return .orange
        default:
            return .gray
        }
    }
}


// PeerRowView moved to separate file

#Preview {
    ContentView()
}