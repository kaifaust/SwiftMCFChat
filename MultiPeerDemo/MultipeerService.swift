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
        return MCPeerID(displayName: UIDevice.current.name)
        #else
        return MCPeerID(displayName: Host.current().localizedName ?? "Unknown")
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
    
    // MARK: - Initialization
    
    override init() {
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
        
        // Set delegates
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }
    
    // MARK: - Public methods
    
    func startHosting() {
        advertiser.startAdvertisingPeer()
    }
    
    func stopHosting() {
        advertiser.stopAdvertisingPeer()
    }
    
    func startBrowsing() {
        browser.startBrowsingForPeers()
    }
    
    func stopBrowsing() {
        browser.stopBrowsingForPeers()
    }
    
    func sendMessage(_ message: String) {
        // Add message to our local list
        DispatchQueue.main.async {
            self.messages.append("Me: \(message)")
        }
        
        guard !connectedPeers.isEmpty else { return }
        
        // Convert string to data
        if let data = message.data(using: .utf8) {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                print("Error sending message: \(error.localizedDescription)")
            }
        }
    }
    
    func disconnect() {
        session.disconnect()
        stopHosting()
        stopBrowsing()
    }
}

// MARK: - MCSessionDelegate
extension MultipeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            
            switch state {
            case .connected:
                print("Connected to: \(peerID.displayName)")
            case .connecting:
                print("Connecting to: \(peerID.displayName)")
            case .notConnected:
                print("Disconnected from: \(peerID.displayName)")
            @unknown default:
                print("Unknown state: \(peerID.displayName)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Convert received data to string message
        if let message = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                self.messages.append("\(peerID.displayName): \(message)")
            }
        }
    }
    
    // Required by protocol but not used for this demo
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept connection requests
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Auto-invite discovered peers
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to start browsing: \(error.localizedDescription)")
    }
}