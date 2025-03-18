//
//  MultipeerService.swift
//  MultiPeerDemo
//
//  Created by Claude on 3/17/25.
//

import Foundation
import MultipeerConnectivity

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

class MultipeerService: NSObject, ObservableObject {
    // MARK: - Properties
    
    // The local peer ID representing this device
    private let myPeerId: MCPeerID = {
        #if canImport(UIKit)
        let peerId = MCPeerID(displayName: UIDevice.current.name)
        print("📱 Created peer ID: \(peerId.displayName)")
        return peerId
        #else
        let peerId = MCPeerID(displayName: Host.current().localizedName ?? "Unknown Mac")
        print("💻 Created peer ID: \(peerId.displayName)")
        return peerId
        #endif
    }()
    
    // Service type should be a unique identifier, following Bonjour naming conventions:
    // 1-15 characters, lowercase letters, numbers, and hyphens (no adjacent hyphens)
    private let serviceType = "multipdemo-chat"
    
    // Active session with other connected peers
    private var session: MCSession
    
    // Advertiser lets others know we're available
    private var advertiser: MCNearbyServiceAdvertiser
    
    // Browser to find other peers
    private var browser: MCNearbyServiceBrowser
    
    // Track connected peers
    @Published var connectedPeers: [MCPeerID] = []
    
    // Track discovered peers and their states
    @Published var discoveredPeers: [PeerInfo] = []
    
    // Messages array
    @Published var messages: [String] = []
    
    // Track if we're currently hosting and browsing
    @Published var isHosting = false
    @Published var isBrowsing = false
    
    // Struct to track peer state information
    struct PeerInfo: Identifiable, Equatable {
        let id: UUID = UUID()
        let peerId: MCPeerID
        var state: PeerState
        var discoveryInfo: [String: String]?
        
        static func == (lhs: PeerInfo, rhs: PeerInfo) -> Bool {
            return lhs.peerId == rhs.peerId
        }
    }
    
    // Enum to track peer states
    enum PeerState: String {
        case discovered = "Discovered"
        case connecting = "Connecting..."
        case connected = "Connected"
        case disconnected = "Disconnected"
        case invitationSent = "Invitation Sent"
        case invitationReceived = "Invitation Received"
    }
    
    // MARK: - Initialization
    
    override init() {
        print("🔄 Initializing MultipeerService")
        
        // Following Apple docs section "Creating a Session"
        // Initialize the session with encryption preference
        session = MCSession(
            peer: myPeerId,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        
        // Initialize the advertiser with our peer ID and service type
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: ["app": "MultiPeerDemo"], // Add discovery info
            serviceType: serviceType
        )
        
        // Initialize the browser with our peer ID and service type
        browser = MCNearbyServiceBrowser(
            peer: myPeerId,
            serviceType: serviceType
        )
        
        super.init()
        
        print("🔄 Setting up delegates")
        // Set delegates for callbacks
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        
        // Add message about initialized service
        DispatchQueue.main.async {
            self.messages.append("System: Service initialized with ID \(self.myPeerId.displayName)")
        }
    }
    
    // MARK: - Public methods
    
    func startHosting() {
        print("📣 Starting advertising for peer ID: \(myPeerId.displayName)")
        DispatchQueue.main.async {
            self.messages.append("System: Started advertising as \(self.myPeerId.displayName)")
        }
        advertiser.startAdvertisingPeer()
        isHosting = true
    }
    
    func stopHosting() {
        print("🛑 Stopping advertising")
        advertiser.stopAdvertisingPeer()
        isHosting = false
        DispatchQueue.main.async {
            self.messages.append("System: Stopped advertising")
        }
    }
    
    func startBrowsing() {
        print("🔍 Starting browsing for peers with service type: \(serviceType)")
        DispatchQueue.main.async {
            self.messages.append("System: Started looking for peers")
        }
        browser.startBrowsingForPeers()
        isBrowsing = true
    }
    
    func stopBrowsing() {
        print("🛑 Stopping browsing")
        browser.stopBrowsingForPeers()
        isBrowsing = false
        DispatchQueue.main.async {
            self.messages.append("System: Stopped looking for peers")
            
            // Clear discovered peers list when stopping browsing
            self.discoveredPeers.removeAll(where: { $0.state == .discovered })
        }
    }
    
    // Invite a specific peer to connect
    func invitePeer(_ peerInfo: PeerInfo) {
        print("📨 Inviting peer: \(peerInfo.peerId.displayName)")
        
        // Update peer state
        updatePeerState(peerInfo.peerId, to: .invitationSent)
        
        DispatchQueue.main.async {
            self.messages.append("System: Sending invitation to \(peerInfo.peerId.displayName)")
        }
        
        // Include discovery info when inviting
        let contextInfo = "MultiPeerDemo invitation".data(using: .utf8)
        browser.invitePeer(peerInfo.peerId, to: session, withContext: contextInfo, timeout: 60)
    }
    
    // Accept a pending invitation
    func acceptInvitation(from peerInfo: PeerInfo, accept: Bool) {
        guard let index = discoveredPeers.firstIndex(where: { $0.peerId == peerInfo.peerId }) else {
            print("⚠️ Cannot find peer to accept/decline invitation: \(peerInfo.peerId.displayName)")
            return
        }
        
        // Check if invitation handler exists for this peer
        if let handler = pendingInvitations[peerInfo.peerId] {
            if accept {
                print("✅ Accepting invitation from: \(peerInfo.peerId.displayName)")
                updatePeerState(peerInfo.peerId, to: .connecting)
                
                DispatchQueue.main.async {
                    self.messages.append("System: Accepting invitation from \(peerInfo.peerId.displayName)")
                }
                
                // Accept the invitation
                handler(true, session)
            } else {
                print("❌ Declining invitation from: \(peerInfo.peerId.displayName)")
                updatePeerState(peerInfo.peerId, to: .discovered)
                
                DispatchQueue.main.async {
                    self.messages.append("System: Declining invitation from \(peerInfo.peerId.displayName)")
                }
                
                // Decline the invitation
                handler(false, nil)
            }
            
            // Remove the handler once used
            pendingInvitations.removeValue(forKey: peerInfo.peerId)
        } else {
            print("⚠️ No pending invitation from: \(peerInfo.peerId.displayName)")
        }
    }
    
    // Store for pending invitations (peerId -> handler)
    private var pendingInvitations: [MCPeerID: (Bool, MCSession?) -> Void] = [:]
    
    // Helper to update peer state in the discoveredPeers array
    private func updatePeerState(_ peerId: MCPeerID, to state: PeerState) {
        DispatchQueue.main.async {
            if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerId }) {
                self.discoveredPeers[index].state = state
            }
        }
    }
    
    func sendMessage(_ message: String) {
        print("📤 Attempting to send message: \(message)")
        
        // Add message to our local list
        DispatchQueue.main.async {
            self.messages.append("Me: \(message)")
        }
        
        guard !session.connectedPeers.isEmpty else { 
            print("❌ No peers connected, cannot send message")
            DispatchQueue.main.async {
                self.messages.append("System: Message not sent - no connected peers")
            }
            return 
        }
        
        // Convert string to data
        if let data = message.data(using: .utf8) {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                print("✅ Message sent to \(session.connectedPeers.count) peers")
            } catch {
                print("❌ Error sending message: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.messages.append("System: Failed to send message - \(error.localizedDescription)")
                }
            }
        }
    }
    
    func disconnect() {
        print("🔌 Disconnecting from all peers")
        session.disconnect()
        stopHosting()
        stopBrowsing()
        
        // Clear all discovered peers
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll()
            self.messages.append("System: Disconnected from all peers")
        }
        
        // Clear pending invitations
        pendingInvitations.removeAll()
    }
}

// MARK: - MCSessionDelegate
extension MultipeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("🔄 Peer \(peerID.displayName) state changed to: \(state.rawValue)")
        
        // Update UI on main thread
        DispatchQueue.main.async {
            // Update connected peers list
            self.connectedPeers = session.connectedPeers
            
            switch state {
            case .connected:
                print("✅ Connected to: \(peerID.displayName)")
                self.messages.append("System: Connected to \(peerID.displayName)")
                print("🔢 Total connected peers: \(session.connectedPeers.count)")
                print("📋 Connected peers list: \(session.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
                
                // Update peer state in discovered peers list
                self.updatePeerState(peerID, to: .connected)
                
                // If we reach maximum peers, consider stopping advertising/browsing
                if session.connectedPeers.count >= 7 { // Max is 8 including local peer
                    print("⚠️ Approaching maximum peer limit (8)")
                    self.messages.append("System: Warning - Approaching maximum peer limit")
                }
            case .connecting:
                print("⏳ Connecting to: \(peerID.displayName)")
                self.messages.append("System: Connecting to \(peerID.displayName)...")
                
                // Update peer state in discovered peers list
                self.updatePeerState(peerID, to: .connecting)
                
            case .notConnected:
                print("❌ Disconnected from: \(peerID.displayName)")
                self.messages.append("System: Disconnected from \(peerID.displayName)")
                
                // If the peer exists in our discovered list, update its state,
                // otherwise it might have been removed already
                if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
                    self.discoveredPeers[index].state = .disconnected
                }
                
            @unknown default:
                print("❓ Unknown state (\(state.rawValue)) for: \(peerID.displayName)")
                self.messages.append("System: Unknown connection state with \(peerID.displayName)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("📥 Received data from: \(peerID.displayName) (\(data.count) bytes)")
        
        // Convert received data to string message
        if let message = String(data: data, encoding: .utf8) {
            print("📩 Message content: \(message)")
            DispatchQueue.main.async {
                self.messages.append("\(peerID.displayName): \(message)")
            }
        } else {
            print("❌ Failed to decode message data to string")
            DispatchQueue.main.async {
                self.messages.append("System: Received unreadable message from \(peerID.displayName)")
            }
        }
    }
    
    // Protocol required methods - not used in this demo but implemented with proper logging
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("📡 Received stream from \(peerID.displayName) with name \(streamName) - not implemented in this demo")
        DispatchQueue.main.async {
            self.messages.append("System: Received stream from \(peerID.displayName) - not supported")
        }
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print("📥 Started receiving resource \(resourceName) from \(peerID.displayName) - not implemented in this demo")
        DispatchQueue.main.async {
            self.messages.append("System: Started receiving file from \(peerID.displayName) - not supported")
        }
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            print("❌ Error receiving resource \(resourceName) from \(peerID.displayName): \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.messages.append("System: Error receiving file from \(peerID.displayName)")
            }
        } else {
            print("✅ Finished receiving resource \(resourceName) from \(peerID.displayName) at URL: \(localURL?.path ?? "unknown")")
            DispatchQueue.main.async {
                self.messages.append("System: Received file from \(peerID.displayName) - not supported")
            }
        }
    }
    
    // Method for handling security certificates
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        // Auto-accept all certificates in this demo app
        print("🔐 Received certificate from \(peerID.displayName) - auto-accepting")
        certificateHandler(true)
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📩 Received invitation from peer: \(peerID.displayName)")
        
        // Safely extract context data if provided
        var contextString = "No context provided"
        if let context = context, let contextText = String(data: context, encoding: .utf8) {
            contextString = contextText
        }
        print("📝 Invitation context: \(contextString)")
        
        // Only accept if not already connected
        guard !session.connectedPeers.contains(peerID) else {
            print("⚠️ Already connected to peer: \(peerID.displayName), declining invitation")
            DispatchQueue.main.async {
                self.messages.append("System: Declining duplicate invitation from \(peerID.displayName)")
            }
            invitationHandler(false, nil)
            return
        }
        
        // Store the invitation handler for later use when user accepts/declines
        pendingInvitations[peerID] = invitationHandler
        
        // Check if this peer is already in our list
        DispatchQueue.main.async {
            if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
                // Update existing peer
                self.discoveredPeers[index].state = .invitationReceived
            } else {
                // Add new peer with invitation received state
                self.discoveredPeers.append(PeerInfo(
                    peerId: peerID,
                    state: .invitationReceived
                ))
            }
            
            self.messages.append("System: Received invitation from \(peerID.displayName)")
            self.messages.append("System: Waiting for you to accept or decline")
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Failed to start advertising: \(error.localizedDescription)")
        
        // Check if it's a MCError and provide more specific info
        if let mcError = error as? NSError, mcError.domain == MCErrorDomain {
            let errorType = MCError.Code(rawValue: mcError.code) ?? .unknown
            print("📣 MultipeerConnectivity error: \(errorType)")
        }
        
        DispatchQueue.main.async {
            self.messages.append("System: Failed to start advertising - \(error.localizedDescription)")
            // Reset state
            self.isHosting = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("🔍 Found peer: \(peerID.displayName), info: \(info?.description ?? "none")")
        
        // Only add to discoveredPeers if not already in the list and not connected
        DispatchQueue.main.async {
            // Check if already connected
            if self.session.connectedPeers.contains(peerID) {
                print("⚠️ Peer already connected: \(peerID.displayName)")
                return
            }
            
            // Check if already in discovered list
            if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
                // Update peer info if it has changed state
                if self.discoveredPeers[index].state == .disconnected {
                    self.discoveredPeers[index].state = .discovered
                    self.discoveredPeers[index].discoveryInfo = info
                }
            } else {
                // Add new peer to discovered list
                self.discoveredPeers.append(PeerInfo(
                    peerId: peerID,
                    state: .discovered,
                    discoveryInfo: info
                ))
                
                self.messages.append("System: Discovered new peer \(peerID.displayName)")
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
        
        DispatchQueue.main.async {
            // If peer is connected, leave it in the list, otherwise remove it
            if !self.session.connectedPeers.contains(peerID) {
                // Remove from discovered peers if not connected
                if let index = self.discoveredPeers.firstIndex(where: { 
                    $0.peerId == peerID && $0.state != .connected && $0.state != .connecting 
                }) {
                    self.discoveredPeers.remove(at: index)
                    self.messages.append("System: Lost sight of peer \(peerID.displayName)")
                }
                
                // Remove any pending invitations
                self.pendingInvitations.removeValue(forKey: peerID)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Failed to start browsing: \(error.localizedDescription)")
        
        // Check if it's a MCError and provide more specific info
        if let mcError = error as? NSError, mcError.domain == MCErrorDomain {
            let errorType = MCError.Code(rawValue: mcError.code) ?? .unknown
            print("🔍 MultipeerConnectivity error: \(errorType)")
        }
        
        DispatchQueue.main.async {
            self.messages.append("System: Failed to start browsing - \(error.localizedDescription)")
            // Reset state
            self.isBrowsing = false
        }
    }
}