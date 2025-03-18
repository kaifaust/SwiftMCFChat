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
    @State private var isConnecting = false
    @State private var showInfoAlert = false
    @State private var showPeersList = false
    @State private var showSyncConflictAlert = false
    @State private var showClearConfirmation = false
    @State private var showConnectionRequestAlert = false
    @State private var currentInvitationPeer: MultipeerService.PeerInfo?
    
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
                    
                    if isConnecting {
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
            if isConnecting {
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
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(connectedPeers) { peer in
                                            PeerItemView(peer: peer) {
                                                handlePeerAction(peer)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .frame(height: 90)
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
                                $0.state == .discovered || $0.state == .invitationReceived 
                            }
                            
                            if !availablePeers.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(availablePeers) { peer in
                                            PeerItemView(peer: peer) {
                                                handlePeerAction(peer)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .frame(height: 90)
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
            
            // Connection controls
            HStack {
                Button(action: {
                    isConnecting.toggle()
                    
                    if isConnecting {
                        multipeerService.startHosting()
                        multipeerService.startBrowsing()
                        // Always show peers list when connecting
                        showPeersList = true
                    } else {
                        multipeerService.disconnect()
                        showPeersList = false
                    }
                }) {
                    HStack {
                        Image(systemName: isConnecting ? "network.slash" : "network")
                        Text(isConnecting ? "Disconnect" : "Connect")
                    }
                }
                .buttonStyle(.bordered)
                
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
            multipeerService.messages.append(MultipeerService.ChatMessage.systemMessage("Click Connect to start"))
        }
        // Add universal connection request alert
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
    
    // Handle peer action based on its current state
    private func handlePeerAction(_ peer: MultipeerService.PeerInfo) {
        switch peer.state {
        case .discovered:
            // Invite peer
            multipeerService.invitePeer(peer)
        case .invitationReceived:
            // Show dialog to accept/decline invitation
            showAcceptInvitationDialog(from: peer)
        default:
            // Other states don't need any action or are handled automatically
            break
        }
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
    }
    
    // Determine if peer state is actionable (can be tapped)
    private func isActionable(_ state: MultipeerService.PeerState) -> Bool {
        switch state {
        case .discovered, .invitationReceived:
            return true
        default:
            return false
        }
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
        case .invitationReceived:
            return "envelope.badge"
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
        case .invitationReceived:
            return .pink
        }
    }
}

#Preview {
    ContentView()
}
