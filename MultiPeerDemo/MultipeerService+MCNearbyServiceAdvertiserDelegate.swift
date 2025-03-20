//
//  MultipeerService+MCNearbyServiceAdvertiserDelegate.swift
//  MultiPeerDemo
//
//  Created by Claude on 3/20/25.
//

import Foundation
import MultipeerConnectivity

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📩 Received invitation from peer: \(peerID.displayName)")
        
        // Try to decode the context to extract user identity information
        var senderInfo: [String: String] = [:]
        if let context = context {
            do {
                if let contextDict = try JSONSerialization.jsonObject(with: context, options: []) as? [String: String] {
                    senderInfo = contextDict
                    print("📝 Invitation context: \(senderInfo)")
                }
            } catch {
                print("⚠️ Could not parse invitation context: \(error.localizedDescription)")
            }
        }
        
        // Check if this user is blocked
        if let userId = senderInfo["userId"], isUserBlocked(userId) {
            print("🚫 Declining invitation from blocked user: \(peerID.displayName)")
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Declined invitation from blocked user \(peerID.displayName)"))
            }
            invitationHandler(false, nil)
            return
        }
        
        // Only accept if not already connected
        let connectedPeerIDs = self.sessionConnectedPeers
        guard !connectedPeerIDs.contains(peerID) else {
            print("⚠️ Already connected to peer: \(peerID.displayName), declining invitation")
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Declining duplicate invitation from \(peerID.displayName)"))
            }
            invitationHandler(false, nil)
            return
        }
        
        // Check if we should auto-accept based on mutual knowledge
        if let userId = senderInfo["userId"], shouldAutoConnect(to: userId) {
            // A peer sending an invitation is definitely nearby - set its state
            if let peerIndex = discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
                // Always update isNearby for peers sending invitations
                discoveredPeers[peerIndex].isNearby = true
                print("📡 Marking peer as nearby due to received invitation: \(peerID.displayName)")
            }
            
            // Auto-accept since a peer that sends an invitation is definitely nearby
            print("🤝 Auto-accepting invitation from known peer: \(peerID.displayName) with userId: \(userId)")
            
            // Update peer state in discovered peers list
            self.updatePeerState(peerID, to: PeerState.connecting, reason: "Auto-accepting invitation from known peer")
            
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Auto-accepting invitation from known peer \(peerID.displayName)"))
            }
            
            // We MUST NOT store the invitation handler for auto-accepted invitations
            // Otherwise it will cause duplicate accept attempts
            
            // Accept the invitation
            invitationHandler(true, self.session as MCSession)
            return
        }
        
        // For peers we don't auto-connect with, store the invitation handler for later use
        self.pendingInvitations[peerID] = invitationHandler
        
        // Check if this peer is already in our list
        DispatchQueue.main.async {
            if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
                // Update existing peer - keep as discovered so it appears in Available list
                let oldState = self.discoveredPeers[index].state
                self.discoveredPeers[index].state = .discovered
                
                // IMPORTANT: Always mark a peer sending an invitation as nearby
                self.discoveredPeers[index].isNearby = true
                
                print("🔄 Peer state updated: \(peerID.displayName) from \(oldState.rawValue) to discovered. Reason: Received invitation, making peer available for connection")
                print("📡 Marking peer as nearby due to received invitation: \(peerID.displayName)")
            } else {
                // Add new peer with discovered state
                self.discoveredPeers.append(PeerInfo(
                    peerId: peerID,
                    state: .discovered,
                    discoveryInfo: senderInfo.isEmpty ? nil : senderInfo,
                    isNearby: true
                ))
                print("➕ Added peer to discovered list: \(peerID.displayName) (Status: discovered, from invitation)")
                print("📡 New peer marked as nearby due to received invitation")
            }
            
            self.messages.append(ChatMessage.systemMessage("Received invitation from \(peerID.displayName)"))
            
            // Notify delegate to immediately show connection request
            self.pendingInvitationHandler?(peerID, invitationHandler)
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Failed to start advertising: \(error.localizedDescription)")
        
        // Check if it's a MCError and provide more specific info
        let mcError = error as NSError
        if mcError.domain == MCErrorDomain {
            let errorType = MCError.Code(rawValue: mcError.code) ?? .unknown
            print("📣 MultipeerConnectivity error: \(errorType)")
        }
        
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Failed to start advertising - \(error.localizedDescription)"))
            // Reset state
            self.isHosting = false
        }
    }
}