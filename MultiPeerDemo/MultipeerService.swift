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
    
    // Messages array
    @Published var messages: [String] = []
    
    // Track if we're currently hosting and browsing
    @Published var isHosting = false
    @Published var isBrowsing = false
    
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
        DispatchQueue.main.async {
            self.messages.append("System: Disconnected from all peers")
        }
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
                
                // If we reach maximum peers, consider stopping advertising/browsing
                if session.connectedPeers.count >= 7 { // Max is 8 including local peer
                    print("⚠️ Approaching maximum peer limit (8)")
                    self.messages.append("System: Warning - Approaching maximum peer limit")
                }
            case .connecting:
                print("⏳ Connecting to: \(peerID.displayName)")
                self.messages.append("System: Connecting to \(peerID.displayName)...")
            case .notConnected:
                print("❌ Disconnected from: \(peerID.displayName)")
                self.messages.append("System: Disconnected from \(peerID.displayName)")
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
        
        // Auto-accept connection requests
        print("✅ Auto-accepting invitation from: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.messages.append("System: Received invitation from \(peerID.displayName)")
            self.messages.append("System: Auto-accepting connection")
        }
        invitationHandler(true, session)
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
        
        // Only invite if not already connected
        guard !session.connectedPeers.contains(peerID) else {
            print("⚠️ Peer already connected: \(peerID.displayName)")
            return
        }
        
        // Auto-invite discovered peers
        print("📨 Inviting peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.messages.append("System: Found peer \(peerID.displayName)")
            self.messages.append("System: Sending invitation to \(peerID.displayName)")
        }
        
        // Include discovery info when inviting
        let contextInfo = "MultiPeerDemo invitation".data(using: .utf8)
        browser.invitePeer(peerID, to: session, withContext: contextInfo, timeout: 60)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.messages.append("System: Lost sight of peer \(peerID.displayName)")
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