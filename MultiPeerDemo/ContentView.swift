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
    
    var body: some View {
        VStack {
            // Header with more status information
            HStack {
                Text("MultipeerDemo")
                    .font(.headline)
                
                Spacer()
                
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
            
            // Nearby devices section
            if isConnecting && !multipeerService.discoveredPeers.isEmpty {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Nearby Devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
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
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(multipeerService.discoveredPeers) { peer in
                                    PeerItemView(peer: peer) {
                                        handlePeerAction(peer)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 90)
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
                    ForEach(Array(multipeerService.messages.enumerated()), id: \.element) { index, message in
                        HStack {
                            if message.starts(with: "System:") {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.gray)
                                
                                Text(message)
                                    .foregroundColor(.gray)
                                    .italic()
                                    .font(.footnote)
                            } else if message.starts(with: "Me:") {
                                Text(message)
                                    .foregroundColor(.blue)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                Text(message)
                                    .padding(6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .id(index)
                        .padding(.vertical, 2)
                    }
                    .onChange(of: multipeerService.messages.count) { _ in
                        if !multipeerService.messages.isEmpty {
                            withAnimation {
                                scrollView.scrollTo(multipeerService.messages.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            
            // Connection controls
            HStack {
                Button(action: {
                    isConnecting.toggle()
                    
                    if isConnecting {
                        multipeerService.startHosting()
                        multipeerService.startBrowsing()
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
            multipeerService.messages.append("System: Welcome to MultipeerDemo")
            multipeerService.messages.append("System: Click Connect to start")
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        // Check for accept/decline commands (for macOS compatibility)
        if messageText.lowercased().starts(with: "accept ") {
            let peerName = messageText.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
            if let peerInfo = multipeerService.discoveredPeers.first(where: { 
                $0.peerId.displayName == peerName && $0.state == .invitationReceived 
            }) {
                multipeerService.acceptInvitation(from: peerInfo, accept: true)
                multipeerService.messages.append("System: Accepted invitation from \(peerName)")
            } else {
                multipeerService.messages.append("System: Could not find pending invitation from \(peerName)")
            }
        } else if messageText.lowercased().starts(with: "decline ") {
            let peerName = messageText.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
            if let peerInfo = multipeerService.discoveredPeers.first(where: { 
                $0.peerId.displayName == peerName && $0.state == .invitationReceived
            }) {
                multipeerService.acceptInvitation(from: peerInfo, accept: false)
                multipeerService.messages.append("System: Declined invitation from \(peerName)")
            } else {
                multipeerService.messages.append("System: Could not find pending invitation from \(peerName)")
            }
        } else {
            // Regular message
            multipeerService.sendMessage(messageText)
        }
        
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
        #if canImport(UIKit) && !os(macOS)
        // iOS implementation with UIAlertController
        let alert = UIAlertController(
            title: "Connection Request",
            message: "\(peer.peerId.displayName) wants to connect. Do you want to accept?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
            multipeerService.acceptInvitation(from: peer, accept: true)
        })
        
        alert.addAction(UIAlertAction(title: "Decline", style: .cancel) { _ in
            multipeerService.acceptInvitation(from: peer, accept: false)
        })
        
        // Present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
        #else
        // Use SwiftUI alert for macOS
        // This is a simplified approach for the demo
        // In a real app, you would have a more sophisticated approach
        let acceptAction = {
            multipeerService.acceptInvitation(from: peer, accept: true)
        }
        
        let declineAction = {
            multipeerService.acceptInvitation(from: peer, accept: false)
        }
        
        // For macOS we'll add a system message with accept/decline options
        DispatchQueue.main.async {
            multipeerService.messages.append("System: Connection request from \(peer.peerId.displayName)")
            multipeerService.messages.append("System: Type 'accept \(peer.peerId.displayName)' or 'decline \(peer.peerId.displayName)'")
            
            // In a real app, you'd use a proper alert or dialog here
            // This is just a workaround for this demo
        }
        #endif
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
