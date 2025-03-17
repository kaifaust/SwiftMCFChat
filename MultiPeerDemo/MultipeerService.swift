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
    
    // Service type should be a unique identifier, up to 15 characters
    private let serviceType = "mpd-messages"
    
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
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        
        browser = MCNearbyServiceBrowser(
            peer: myPeerId,
            serviceType: serviceType
        )
        
        super.init()
        
        print("🔄 Setting up delegates")
        // Set delegates
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
        
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            
            switch state {
            case .connected:
                print("✅ Connected to: \(peerID.displayName)")
                self.messages.append("System: Connected to \(peerID.displayName)")
                print("🔢 Total connected peers: \(session.connectedPeers.count)")
                print("📋 Connected peers list: \(session.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
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
        print("📥 Received data from: \(peerID.displayName)")
        
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
    
    // Required by protocol but not used for this demo
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("📡 Received stream from \(peerID.displayName) with name \(streamName) - not implemented")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print("📥 Started receiving resource \(resourceName) from \(peerID.displayName) - not implemented")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            print("❌ Error receiving resource \(resourceName) from \(peerID.displayName): \(error.localizedDescription)")
        } else {
            print("✅ Finished receiving resource \(resourceName) from \(peerID.displayName)")
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📩 Received invitation from peer: \(peerID.displayName)")
        
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
        
        // Auto-invite discovered peers
        print("📨 Inviting peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.messages.append("System: Found peer \(peerID.displayName)")
            self.messages.append("System: Sending invitation to \(peerID.displayName)")
        }
        
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.messages.append("System: Lost sight of peer \(peerID.displayName)")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Failed to start browsing: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.messages.append("System: Failed to start browsing - \(error.localizedDescription)")
            // Reset state
            self.isBrowsing = false
        }
    }
}