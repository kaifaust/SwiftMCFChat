//
//  MultipeerService+MCSessionDelegate.swift
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

// MARK: - MCSessionDelegate
extension MultipeerService: MCSessionDelegate {
    // No need for typealias since SyncDecision is defined in the main class
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("🔄 Peer \(peerID.displayName) state changed to: \(state.rawValue)")
        
        // Update UI on main thread
        DispatchQueue.main.async {
            // Update connected peers list
            self.connectedPeers = session.connectedPeers
            
            switch state {
            case .connected:
                print("✅ Connected to: \(peerID.displayName)")
                self.messages.append(ChatMessage.systemMessage("Connected to \(peerID.displayName)"))
                let connectedPeerIDs = self.sessionConnectedPeers
                print("🔢 Total connected peers: \(connectedPeerIDs.count)")
                print("📋 Connected peers list: \(connectedPeerIDs.map { $0.displayName }.joined(separator: ", "))")
                
                // Update peer state in discovered peers list
                self.updatePeerState(peerID, to: .connected, reason: "Session connection established")
                
                // Store peer as known if we have their userId
                if let discoveryInfo = self.discoveredPeers.first(where: { $0.peerId == peerID })?.discoveryInfo,
                   let userId = discoveryInfo["userId"] {
                    self.updateKnownPeer(displayName: peerID.displayName, userId: userId)
                }
                
                // Sync messages with the newly connected peer
                self.syncMessages(with: peerID)
                
                // If we reach maximum peers, consider stopping advertising/browsing
                if session.connectedPeers.count >= 7 { // Max is 8 including local peer
                    print("⚠️ Approaching maximum peer limit (8)")
                    self.messages.append(ChatMessage.systemMessage("Warning - Approaching maximum peer limit"))
                }
            case .connecting:
                print("⏳ Connecting to: \(peerID.displayName)")
                self.messages.append(ChatMessage.systemMessage("Connecting to \(peerID.displayName)..."))
                
                // Update peer state in discovered peers list
                self.updatePeerState(peerID, to: .connecting, reason: "Session moving to connecting state")
                
            case .notConnected:
                print("❌ Disconnected from: \(peerID.displayName)")
                self.messages.append(ChatMessage.systemMessage("Disconnected from \(peerID.displayName)"))
                
                // If the peer exists in our discovered list, update its state,
                // otherwise it might have been removed already
                if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
                    // If we were in invitationSent state and now not connected, it means invitation was declined
                    if self.discoveredPeers[index].state == .invitationSent {
                        self.discoveredPeers[index].state = .rejected
                        print("🔄 Peer state change: \(peerID.displayName) changed from invitationSent to rejected. Reason: Invitation declined (inferred from disconnect)")
                        print("📱 Device placement: \(peerID.displayName) will appear in 'Other Devices' section")
                        self.messages.append(ChatMessage.systemMessage("Invitation declined by \(peerID.displayName)"))
                    } else if self.discoveredPeers[index].state == .connected {
                        // When a connected peer disconnects, handle differently based on whether it's saved
                        let userId = self.discoveredPeers[index].discoveryInfo?["userId"]
                        let isKnown = userId != nil && self.knownPeers.contains(where: { $0.userId == userId })
                        let isSyncEnabled = userId != nil && self.syncEnabledPeers.contains(userId!)
                        
                        if isKnown || isSyncEnabled {
                            // Create a disconnected state for previously connected peers
                            print("🔄 Setting previously connected peer to disconnected state: \(peerID.displayName)")
                            self.discoveredPeers[index].state = .disconnected
                            // Initially set as not nearby - the browser will update this if peer is actually nearby
                            self.discoveredPeers[index].isNearby = false
                            print("📡 Setting disconnected peer as not nearby by default: \(peerID.displayName)")
                        } else {
                            // Only remove unknown peers
                            print("🗑️ Removing connected peer that disconnected: \(peerID.displayName)")
                            self.discoveredPeers.remove(at: index)
                        }
                    }
                }
                
            @unknown default:
                print("❓ Unknown state (\(state.rawValue)) for: \(peerID.displayName)")
                self.messages.append(ChatMessage.systemMessage("Unknown connection state with \(peerID.displayName)"))
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("📥 Received data from: \(peerID.displayName) (\(data.count) bytes)")
        
        // Process received data in order of priority
        if let messageType = getMessageType(from: data) {
            switch messageType {
            case "forget_device":
                handleForgetDeviceRequest(data: data, fromPeer: peerID)
            case "sync_decision":
                handleSyncDecision(data: data, fromPeer: peerID)
            case "sync":
                handleMessageSync(data: data, fromPeer: peerID)
            default:
                handleChatMessage(data: data, fromPeer: peerID)
            }
        } else {
            handleChatMessage(data: data, fromPeer: peerID)
        }
    }
    
    // MARK: - Message Processing Helpers
    
    /// Get the message type from data if possible
    func getMessageType(from data: Data) -> String? {
        // Try to decode just the type field to determine message type
        struct MessageType: Codable {
            let type: String
        }
        
        do {
            let messageType = try JSONDecoder().decode(MessageType.self, from: data)
            return messageType.type
        } catch {
            return nil
        }
    }
    
    /// Handle a forget device request
    private func handleForgetDeviceRequest(data: Data, fromPeer peerID: MCPeerID) {
        do {
            let forgetRequest = try JSONDecoder().decode(ForgetDeviceRequest.self, from: data)
            print("🧹 Received forget device request for userId: \(forgetRequest.userId)")
            handleForgetDeviceRequest(userId: forgetRequest.userId, fromPeer: peerID)
        } catch {
            print("❌ Failed to decode forget device request: \(error.localizedDescription)")
        }
    }
    
    /// Handle a sync decision
    private func handleSyncDecision(data: Data, fromPeer peerID: MCPeerID) {
        do {
            // Explicitly use MultipeerService.SyncDecision to avoid ambiguity
            let syncDecision = try JSONDecoder().decode(MultipeerService.SyncDecision.self, from: data)
            print("🔄 Received sync decision from \(peerID.displayName): \(syncDecision.useRemote ? "they're using our history" : "they're keeping their history")")
            handleSyncDecision(theyUseRemote: syncDecision.useRemote, fromPeer: peerID)
        } catch {
            print("❌ Failed to decode sync decision: \(error.localizedDescription)")
        }
    }
    
    /// Handle a message sync
    private func handleMessageSync(data: Data, fromPeer peerID: MCPeerID) {
        do {
            let syncMessage = try JSONDecoder().decode(SyncMessage.self, from: data)
            print("🔄 Received sync message with \(syncMessage.messages.count) messages")
            handleMessageSync(messages: syncMessage.messages, fromPeer: peerID)
        } catch {
            print("❌ Failed to decode sync message: \(error.localizedDescription)")
        }
    }
    
    /// Handle a regular chat message
    private func handleChatMessage(data: Data, fromPeer peerID: MCPeerID) {
        do {
            let receivedMessage = try JSONDecoder().decode(ChatMessage.self, from: data)
            print("📩 Message content: \(receivedMessage.content) from \(receivedMessage.senderName)")
            
            DispatchQueue.main.async {
                // Add the message to our local list if we don't already have it
                if !self.messages.contains(where: { $0.id == receivedMessage.id }) {
                    self.messages.append(receivedMessage)
                    
                    // Sort messages by timestamp
                    self.messages.sort(by: { $0.timestamp < $1.timestamp })
                }
            }
        } catch {
            print("❌ Failed to decode message data: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Received unreadable message from \(peerID.displayName)"))
            }
        }
    }
    
    /// Handle a request from another device to forget a user ID
    private func handleForgetDeviceRequest(userId: String, fromPeer peerID: MCPeerID) {
        print("🔄 Processing forget device request for userId: \(userId) from \(peerID.displayName)")
        
        // Extract sender userId from discoveryInfo if available
        var senderUserId: String? = nil
        if let index = discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
            senderUserId = discoveredPeers[index].discoveryInfo?["userId"]
        }
        
        // Get the current state on the main thread to avoid threading issues
        DispatchQueue.main.async {
            let wasBrowsing = self.isBrowsing
            let wasHosting = self.isHosting
            
            // If we have a sender ID, also forget them (bidirectional forget)
            if let senderUserId = senderUserId {
                // Also forget the device that sent the forget request
                print("🧹 Also forgetting the sender device with userId: \(senderUserId)")
                
                // Remove sender from known peers
                self.knownPeers.removeAll { $0.userId == senderUserId }
                
                // Remove sender from sync-enabled peers
                self.syncEnabledPeers.remove(senderUserId)
                
                // Update the discovered peers list - mark as discovered instead of disconnected
                for index in (0..<self.discoveredPeers.count).reversed() {
                    if self.discoveredPeers[index].discoveryInfo?["userId"] == senderUserId {
                        let peer = self.discoveredPeers[index]
                        
                        if self.discoveredPeers[index].isNearby {
                            // If the peer is nearby, update its state to "discovered"
                            self.discoveredPeers[index].state = PeerState.discovered
                            print("🔄 Peer \(peer.peerId.displayName) forgotten via bidirectional request - set to 'discovered' state")
                        } else {
                            // If not nearby, remove it completely
                            self.discoveredPeers.remove(at: index)
                            print("🔄 Peer \(peer.peerId.displayName) forgotten and removed via bidirectional request (not nearby)")
                        }
                    }
                }
                
                // Save these changes immediately
                self.saveKnownPeers()
                self.saveSyncEnabledPeers()
            }
            
            // First, break the active connection (this is needed for proper rediscovery)
            if self.session.connectedPeers.contains(peerID) {
                // Need to recreate the session to disconnect this specific peer
                
                // Stop browsing and advertising temporarily
                if wasBrowsing {
                    self.stopBrowsing()
                }
                if wasHosting {
                    self.stopHosting()
                }
                
                // Disconnect the session
                self.session.disconnect()
                
                // Create a new session
                self.session = MCSession(
                    peer: self.myPeerId,
                    securityIdentity: nil,
                    encryptionPreference: .required
                )
                self.session.delegate = self
                
                // Remove all connected peers when session is recreated
                self.discoveredPeers.removeAll(where: { $0.state == PeerState.connected })
                self.connectedPeers = []
                
                // Restart browsing and advertising
                if wasBrowsing {
                    self.startBrowsing()
                }
                if wasHosting {
                    self.startHosting()
                }
            }
            
            // Handle the requested userId to forget
            
            // Remove from known peers
            self.knownPeers.removeAll { $0.userId == userId }
            
            // Remove from sync-enabled peers to ensure it's fully forgotten
            self.syncEnabledPeers.remove(userId)
            
            // Update the discovered peers list for the requested user to forget
            for index in (0..<self.discoveredPeers.count).reversed() {
                if self.discoveredPeers[index].discoveryInfo?["userId"] == userId {
                    let peer = self.discoveredPeers[index]
                    
                    if self.discoveredPeers[index].isNearby {
                        // If the peer is nearby, update its state to "discovered"
                        self.discoveredPeers[index].state = PeerState.discovered
                        print("🔄 Peer \(peer.peerId.displayName) forgotten via request - set to 'discovered' state")
                    } else {
                        // If not nearby, remove it completely
                        self.discoveredPeers.remove(at: index)
                        print("🔄 Peer \(peer.peerId.displayName) forgotten and removed via request (not nearby)")
                    }
                }
            }
            
            // Don't block - that's a user preference
            
            // Save changes
            self.saveKnownPeers()
            self.saveSyncEnabledPeers()
            
            self.messages.append(ChatMessage.systemMessage("Removed peer from known devices at their request"))
        }
    }
    
    // Handle an incoming sync decision from another peer
    private func handleSyncDecision(theyUseRemote: Bool, fromPeer peerID: MCPeerID) {
        // The remote device has already made a decision about which history to keep
        // If theyUseRemote=true, they want to use our history (so we keep our local messages)
        // If theyUseRemote=false, they want to keep their history (we should use their messages)
        
        // Check if we have a pending decision for this peer
        guard hasPendingSyncDecision, pendingSyncPeer == peerID,
              let remoteMessages = pendingSyncs[peerID] else {
            print("⚠️ Received sync decision but no pending sync for this peer")
            return
        }
        
        // Apply the decision automatically
        DispatchQueue.main.async {
            // Clear UI alert if it's showing
            self.hasPendingSyncDecision = false
            
            // Apply the decision
            if theyUseRemote {
                // They chose to use our history, so we keep our local messages
                print("✅ Remote device adopted our history")
                self.messages.append(ChatMessage.systemMessage("\(peerID.displayName) adopted our message history"))
            } else {
                // They chose to keep their history, so we use their messages
                print("ℹ️ Remote device kept their history, adopting it")
                
                // Keep only our system messages
                let ourSystemMessages = self.messages.filter { $0.isSystemMessage }
                
                // Get user messages from remote
                let remoteUserMessages = remoteMessages.filter { !$0.isSystemMessage }
                
                // Combine and sort
                self.messages = ourSystemMessages + remoteUserMessages
                self.messages.sort(by: { $0.timestamp < $1.timestamp })
                
                // Add info message
                self.messages.append(ChatMessage.systemMessage("Adopted message history from \(peerID.displayName)"))
            }
            
            // Clean up
            self.pendingSyncs.removeValue(forKey: peerID)
            self.pendingSyncPeer = nil
        }
    }
    
    // Handle message sync from another peer
    private func handleMessageSync(messages syncedMessages: [ChatMessage], fromPeer peerID: MCPeerID) {
        print("🔄 Received message sync from \(peerID.displayName) with \(syncedMessages.count) messages")
        
        // Extract userId from discoveryInfo if available
        var userId: String? = nil
        if let index = discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
            userId = discoveredPeers[index].discoveryInfo?["userId"]
        }
        
        DispatchQueue.main.async {
            // If we have the userId, update the sync status if not already done
            if let userId = userId, !self.syncEnabledPeers.contains(userId) {
                // Auto-enable sync for peers we're actively syncing with
                self.syncEnabledPeers.insert(userId)
                if let index = self.knownPeers.firstIndex(where: { $0.userId == userId }) {
                    self.knownPeers[index].syncEnabled = true
                }
                self.saveSyncEnabledPeers()
            }
            
            // Filter out system messages for conflict detection
            let localUserMessages = self.messages.filter { !$0.isSystemMessage }
            let remoteUserMessages = syncedMessages.filter { !$0.isSystemMessage }
            
            // If our history and their history are different in significant ways,
            // let the user decide which to keep
            let localOnlyMessages = localUserMessages.filter { localMsg in
                !remoteUserMessages.contains { $0.id == localMsg.id }
            }
            
            let remoteOnlyMessages = remoteUserMessages.filter { remoteMsg in
                !localUserMessages.contains { $0.id == remoteMsg.id }
            }
            
            // If there are differences in both directions, we have a potential conflict
            let hasConflict = !localOnlyMessages.isEmpty && !remoteOnlyMessages.isEmpty
            
            if hasConflict {
                print("⚠️ Message history conflict detected: \(localOnlyMessages.count) local-only messages, \(remoteOnlyMessages.count) remote-only messages")
                
                // Store the remote messages for later resolution
                self.pendingSyncs[peerID] = syncedMessages
                self.pendingSyncPeer = peerID
                self.hasPendingSyncDecision = true
                
                // Add a system message about the conflict
                self.messages.append(ChatMessage.systemMessage("Message history conflict detected with \(peerID.displayName)"))
                self.messages.append(ChatMessage.systemMessage("Choose which history to keep in the conflict resolution dialog"))
            } else {
                // No conflict, just merge messages
                self.mergeMessages(syncedMessages, fromPeer: peerID)
            }
        }
    }
    
    // Merge messages from another peer without conflict resolution
    private func mergeMessages(_ syncedMessages: [ChatMessage], fromPeer peerID: MCPeerID) {
        // Only merge non-system messages
        let remoteUserMessages = syncedMessages.filter { !$0.isSystemMessage }
        var newMessages = [ChatMessage]()
        
        // Add messages we don't already have
        for syncedMessage in remoteUserMessages {
            if !self.messages.contains(where: { $0.id == syncedMessage.id }) {
                newMessages.append(syncedMessage)
            }
        }
        
        // If we have new messages, add them and sort by timestamp
        if !newMessages.isEmpty {
            // Temporarily disable saving while we make batch changes
            let wasInitialLoad = self.isInitialLoad
            self.isInitialLoad = true
            
            // Make all changes at once
            self.messages.append(contentsOf: newMessages)
            self.messages.sort(by: { $0.timestamp < $1.timestamp })
            
            // Add a system message about the sync
            self.messages.append(ChatMessage.systemMessage("Synced \(newMessages.count) messages from \(peerID.displayName)"))
            
            // Restore previous state and trigger a single save
            self.isInitialLoad = wasInitialLoad
            print("✅ Added \(newMessages.count) new messages from sync")
            
            // Manual save once after all changes
            if !self.isInitialLoad {
                saveMessages()
            }
        } else {
            print("ℹ️ No new messages from sync")
        }
    }
    
    // MARK: - Required Session Delegate Methods
    
    // Protocol required methods - not used in this demo but implemented with proper logging
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("📡 Received stream from \(peerID.displayName) with name \(streamName) - not implemented in this demo")
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Received stream from \(peerID.displayName) - not supported"))
        }
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print("📥 Started receiving resource \(resourceName) from \(peerID.displayName) - not implemented in this demo")
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Started receiving file from \(peerID.displayName) - not supported"))
        }
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            print("❌ Error receiving resource \(resourceName) from \(peerID.displayName): \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Error receiving file from \(peerID.displayName)"))
            }
        } else {
            print("✅ Finished receiving resource \(resourceName) from \(peerID.displayName) at URL: \(localURL?.path ?? "unknown")")
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Received file from \(peerID.displayName) - not supported"))
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