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
    @StateObject private var multipeerService = MultipeerService()
    @State private var messageText = ""
    @State private var isSyncEnabled = true
    @State private var showInfoAlert = false
    @State private var showPeersList = false
    @State private var showSyncConflictAlert = false
    @State private var showClearConfirmation = false
    @State private var showConnectionRequestAlert = false
    @State private var currentInvitationPeer: MultipeerService.PeerInfo?
    @State private var showPeerContextMenu = false
    @State private var selectedPeer: MultipeerService.PeerInfo?
    @State private var showForgetConfirmation = false
    
    var body: some View {
        VStack {
            // Header with more status information
            HStack {
                Text("MultipeerDemo")
                    .font(.headline)
                
                Spacer()
                
                // Clear history button
                Button(action: {
                    showClearConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                
                // Connection status with more details
                HStack {
                    Circle()
                        .fill(multipeerService.connectedPeers.isEmpty ? .red : .green)
                        .frame(width: 10, height: 10)
                    
                    Text("\(multipeerService.connectedPeers.count) connected")
                        .font(.caption)
                    
                    if isSyncEnabled {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                    }
                }
                
                Button(action: {
                    showInfoAlert = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
                .alert("Connection Information", isPresented: $showInfoAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Hosting: \(multipeerService.isHosting ? "Yes" : "No")\nBrowsing: \(multipeerService.isBrowsing ? "Yes" : "No")\nPeers: \(multipeerService.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
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
            
            // Devices section with Connections and Available subsections
            if isSyncEnabled {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Devices")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            showPeersList.toggle()
                        }) {
                            Label(showPeersList ? "Hide" : "Show", systemImage: showPeersList ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    if showPeersList {
                        // Connected devices section
                        VStack(alignment: .leading) {
                            Text("Connections")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                            
                            let connectedPeers = multipeerService.discoveredPeers.filter { 
                                $0.state == .connected || $0.state == .connecting
                            }
                            
                            if !connectedPeers.isEmpty {
                                ForEach(connectedPeers) { peer in
                                    PeerRowView(peer: peer, action: {
                                        handlePeerAction(peer)
                                    }, onForget: {
                                        selectedPeer = peer
                                        showForgetConfirmation = true
                                    }, onBlock: {
                                        if let userId = peer.discoveryInfo?["userId"] {
                                            multipeerService.blockUser(userId: userId)
                                        }
                                    })
                                    .environmentObject(multipeerService)
                                    .padding(.vertical, 2)
                                }
                            } else {
                                HStack {
                                    Spacer()
                                    Text("No connected devices")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        // Available devices section
                        VStack(alignment: .leading) {
                            Text("Available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                            
                            let availablePeers = multipeerService.discoveredPeers.filter { 
                                $0.state == .discovered 
                            }
                            
                            if !availablePeers.isEmpty {
                                ForEach(availablePeers) { peer in
                                    PeerRowView(peer: peer, action: {
                                        handlePeerAction(peer)
                                    }, onForget: {
                                        selectedPeer = peer
                                        showForgetConfirmation = true
                                    }, onBlock: {
                                        if let userId = peer.discoveryInfo?["userId"] {
                                            multipeerService.blockUser(userId: userId)
                                        }
                                    })
                                    .environmentObject(multipeerService)
                                    .padding(.vertical, 2)
                                }
                            } else {
                                HStack {
                                    Spacer()
                                    Text("No available devices found")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
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
                                scrollView.scrollTo(multipeerService.messages.count - 1, anchor: .bottom)
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
            
            // Device sync controls
            HStack {
                HStack {
                    Text("Sync Devices")
                    Toggle("", isOn: $isSyncEnabled)
                        .labelsHidden()
                        .onChange(of: isSyncEnabled) { oldValue, newValue in
                            if newValue {
                                multipeerService.startHosting()
                                multipeerService.startBrowsing()
                                // Always show peers list when sync is enabled
                                showPeersList = true
                            } else {
                                multipeerService.disconnect()
                                showPeersList = false
                            }
                        }
                }
                
                Spacer()
                
                // Connected peers with improved formatting and badge count
                if !multipeerService.connectedPeers.isEmpty {
                    HStack {
                        Image(systemName: multipeerService.connectedPeers.count > 1 ? "person.3.fill" : "person.fill")
                            .foregroundColor(.green)
                        
                        Text(multipeerService.connectedPeers.map { $0.displayName }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.trailing, 4)
                        
                        // Add badge with count
                        if multipeerService.connectedPeers.count > 0 {
                            Text("\(multipeerService.connectedPeers.count)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .padding()
            
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
        .onAppear {
            multipeerService.messages.append(MultipeerService.ChatMessage.systemMessage("Welcome to MultipeerDemo"))
            multipeerService.messages.append(MultipeerService.ChatMessage.systemMessage("Sync is enabled by default"))
            
            // Start sync automatically since it's enabled by default
            multipeerService.startHosting()
            multipeerService.startBrowsing()
            showPeersList = true
            
            // Register for invitation handling
            multipeerService.pendingInvitationHandler = { peerID, invitationHandler in
                // Find or create a PeerInfo for this peer
                let peerInfo: MultipeerService.PeerInfo
                if let existing = multipeerService.discoveredPeers.first(where: { $0.peerId == peerID }) {
                    peerInfo = existing
                } else {
                    peerInfo = MultipeerService.PeerInfo(peerId: peerID, state: .discovered)
                }
                
                // Show the connection request dialog immediately
                currentInvitationPeer = peerInfo
                showConnectionRequestAlert = true
            }
        }
        // Add universal connection request alert
        // Connection request alert
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
        
        // Forget device confirmation
        .alert("Forget Device", isPresented: $showForgetConfirmation) {
            Button("Cancel", role: .cancel) { }
            
            Button("Forget", role: .destructive) {
                if let peer = selectedPeer, let userId = peer.discoveryInfo?["userId"] {
                    multipeerService.forgetDevice(userId: userId)
                }
                selectedPeer = nil
            }
            
            Button("Forget & Block", role: .destructive) {
                if let peer = selectedPeer, let userId = peer.discoveryInfo?["userId"] {
                    multipeerService.forgetDevice(userId: userId, andBlock: true)
                }
                selectedPeer = nil
            }
        } message: {
            if let peer = selectedPeer {
                Text("Do you want to forget device \(peer.peerId.displayName)? This will remove it from known peers and auto-connect list.")
            } else {
                Text("Do you want to forget this device?")
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        // Send message directly without any platform-specific commands
        multipeerService.sendMessage(messageText)
        messageText = ""
    }
    
    // Handle peer action based on its current state
    private func handlePeerAction(_ peer: MultipeerService.PeerInfo) {
        if peer.state == .discovered {
            // Invite peer
            multipeerService.invitePeer(peer)
        }
        // All other states don't need manual action or are handled automatically
    }
    
    // Show accept/decline invitation dialog
    private func showAcceptInvitationDialog(from peer: MultipeerService.PeerInfo) {
        // Use a unified SwiftUI approach for all platforms
        currentInvitationPeer = peer
        showConnectionRequestAlert = true
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
            
            // Peer state
            Text(peer.state.rawValue)
                .font(.caption2)
                .foregroundColor(colorForState(peer.state))
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
            if peer.state == .connected || peer.state == .discovered {
                if let userId = peer.discoveryInfo?["userId"] {
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
        return state == .discovered
    }
    
    // Get appropriate icon for peer state
    private func iconForState(_ state: MultipeerService.PeerState) -> String {
        switch state {
        case .discovered:
            return "person.crop.circle.badge.plus"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "checkmark.circle"
        case .disconnected:
            return "x.circle"
        case .invitationSent:
            return "envelope"
        default:
            return "person.crop.circle.badge.questionmark"
        }
    }
    
    // Get appropriate color for peer state
    private func colorForState(_ state: MultipeerService.PeerState) -> Color {
        switch state {
        case .discovered:
            return .blue
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .disconnected:
            return .red
        case .invitationSent:
            return .purple
        default:
            return .gray
        }
    }
}

// View for displaying a peer as a horizontal row with action buttons
struct PeerRowView: View {
    let peer: MultipeerService.PeerInfo
    let action: () -> Void
    let onForget: () -> Void
    let onBlock: () -> Void
    @EnvironmentObject var multipeerService: MultipeerService
    
    var body: some View {
        HStack {
            // Main content - this part will be clickable for "discovered" peers
            HStack {
                // Peer icon
                Image(systemName: iconForState(peer.state))
                    .font(.system(size: 18))
                    .foregroundColor(colorForState(peer.state))
                    .frame(width: 32, height: 32)
                    .background(colorForState(peer.state).opacity(0.2))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    // Peer name
                    Text(peer.peerId.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    // Peer state
                    Text(peer.state.rawValue)
                        .font(.caption)
                        .foregroundColor(colorForState(peer.state))
                }
                
                Spacer()
            }
            .contentShape(Rectangle()) // Make the entire area tappable
            .onTapGesture {
                if isActionable(peer.state) {
                    action()
                }
            }
            
            // Action buttons - these remain independently clickable
            HStack(spacing: 8) {
                // Forget button
                Button(action: onForget) {
                    Text("Forget")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                // Block button
                Button(action: onBlock) {
                    Text("Block")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isActionable(peer.state) ? colorForState(peer.state).opacity(0.3) : Color.secondary.opacity(0.3), 
                    lineWidth: isActionable(peer.state) ? 1.5 : 1
                )
        )
        .opacity(isActionable(peer.state) ? 1.0 : 0.85)
    }
    
    // Determine if peer state is actionable (can be tapped to connect)
    private func isActionable(_ state: MultipeerService.PeerState) -> Bool {
        return state == .discovered
    }
    
    // Get appropriate icon for peer state
    private func iconForState(_ state: MultipeerService.PeerState) -> String {
        switch state {
        case .discovered:
            return "person.crop.circle.badge.plus"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "checkmark.circle"
        case .disconnected:
            return "x.circle"
        case .invitationSent:
            return "envelope"
        default:
            return "person.crop.circle.badge.questionmark"
        }
    }
    
    // Get appropriate color for peer state
    private func colorForState(_ state: MultipeerService.PeerState) -> Color {
        switch state {
        case .discovered:
            return .blue
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .disconnected:
            return .red
        case .invitationSent:
            return .purple
        default:
            return .gray
        }
    }
}

#Preview {
    ContentView()
}
