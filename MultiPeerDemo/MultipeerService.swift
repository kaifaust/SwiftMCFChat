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
    
    // User identity that remains consistent across devices
    let userId: UUID
    private let userName = "Me" // The user is always displayed as "Me"
    
    // UserDefaults keys
    private enum UserDefaultsKeys {
        static let userId = "MultipeerDemo.userId"
        static let messages = "MultipeerDemo.messages"
    }
    
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
    
    // Messages array with ChatMessage objects instead of strings
    @Published var messages: [ChatMessage] = [] {
        didSet {
            // Save messages to UserDefaults whenever they change
            saveMessages()
        }
    }
    
    // Track devices we're syncing with and their message histories
    private var pendingSyncs: [MCPeerID: [ChatMessage]] = [:]
    
    // Published property to indicate if there are pending sync decisions
    @Published var hasPendingSyncDecision = false
    @Published var pendingSyncPeer: MCPeerID? = nil
    
    // Track if we're currently hosting and browsing
    @Published var isHosting = false
    @Published var isBrowsing = false
    
    // Message model to track sender identity
    struct ChatMessage: Identifiable, Codable, Equatable {
        let id: UUID
        let senderId: UUID
        let senderName: String
        let content: String
        let isSystemMessage: Bool
        let timestamp: Date
        
        static func systemMessage(_ content: String) -> ChatMessage {
            ChatMessage(
                id: UUID(),
                senderId: UUID(), // System messages have random sender IDs
                senderName: "System",
                content: content,
                isSystemMessage: true,
                timestamp: Date()
            )
        }
        
        static func userMessage(senderId: UUID, senderName: String, content: String) -> ChatMessage {
            ChatMessage(
                id: UUID(),
                senderId: senderId,
                senderName: senderName,
                content: content,
                isSystemMessage: false,
                timestamp: Date()
            )
        }
    }
    
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
        
        // Load or create a persistent user ID
        if let storedUserIdString = UserDefaults.standard.string(forKey: UserDefaultsKeys.userId),
           let storedUserId = UUID(uuidString: storedUserIdString) {
            print("📱 Loaded existing user ID: \(storedUserIdString)")
            userId = storedUserId
        } else {
            // Create a new user ID and save it
            let newUserId = UUID()
            UserDefaults.standard.set(newUserId.uuidString, forKey: UserDefaultsKeys.userId)
            print("📱 Created new user ID: \(newUserId.uuidString)")
            userId = newUserId
        }
        
        // Following Apple docs section "Creating a Session"
        // Initialize the session with encryption preference
        session = MCSession(
            peer: myPeerId,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        
        // Initialize the advertiser with our peer ID and service type
        // Include user ID in discovery info to help identify the same user across devices
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: ["app": "MultiPeerDemo", "userId": userId.uuidString], // Add user identity
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
        
        // Load saved messages
        loadMessages()
        
        // Add message about initialized service
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Service initialized with ID \(self.myPeerId.displayName)"))
        }
    }
    
    // MARK: - Public methods
    
    func startHosting() {
        print("📣 Starting advertising for peer ID: \(myPeerId.displayName)")
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Started advertising as \(self.myPeerId.displayName)"))
        }
        advertiser.startAdvertisingPeer()
        isHosting = true
    }
    
    func stopHosting() {
        print("🛑 Stopping advertising")
        advertiser.stopAdvertisingPeer()
        isHosting = false
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Stopped advertising"))
        }
    }
    
    func startBrowsing() {
        print("🔍 Starting browsing for peers with service type: \(serviceType)")
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Started looking for peers"))
        }
        browser.startBrowsingForPeers()
        isBrowsing = true
    }
    
    func stopBrowsing() {
        print("🛑 Stopping browsing")
        browser.stopBrowsingForPeers()
        isBrowsing = false
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Stopped looking for peers"))
            
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
            self.messages.append(ChatMessage.systemMessage("Sending invitation to \(peerInfo.peerId.displayName)"))
        }
        
        // Include user identity with invitation context
        let invitationContext = ["userId": userId.uuidString, "userName": userName]
        let contextData = try? JSONEncoder().encode(invitationContext)
        browser.invitePeer(peerInfo.peerId, to: session, withContext: contextData, timeout: 60)
    }
    
    // Accept a pending invitation
    func acceptInvitation(from peerInfo: PeerInfo, accept: Bool) {
        guard discoveredPeers.contains(where: { $0.peerId == peerInfo.peerId }) else {
            print("⚠️ Cannot find peer to accept/decline invitation: \(peerInfo.peerId.displayName)")
            return
        }
        
        // Check if invitation handler exists for this peer
        if let handler = pendingInvitations[peerInfo.peerId] {
            if accept {
                print("✅ Accepting invitation from: \(peerInfo.peerId.displayName)")
                updatePeerState(peerInfo.peerId, to: .connecting)
                
                DispatchQueue.main.async {
                    self.messages.append(ChatMessage.systemMessage("Accepting invitation from \(peerInfo.peerId.displayName)"))
                }
                
                // Accept the invitation
                handler(true, session)
            } else {
                print("❌ Declining invitation from: \(peerInfo.peerId.displayName)")
                updatePeerState(peerInfo.peerId, to: .discovered)
                
                DispatchQueue.main.async {
                    self.messages.append(ChatMessage.systemMessage("Declining invitation from \(peerInfo.peerId.displayName)"))
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
        
        // Create a chat message with user identity
        let chatMessage = ChatMessage.userMessage(
            senderId: userId,
            senderName: userName,
            content: message
        )
        
        // Add message to our local list
        DispatchQueue.main.async {
            self.messages.append(chatMessage)
        }
        
        // If we have no connected peers, just save the message locally
        guard !session.connectedPeers.isEmpty else { 
            print("⚠️ No peers connected, message saved locally")
            return 
        }
        
        // Convert chat message to data and send to connected peers
        do {
            let messageData = try JSONEncoder().encode(chatMessage)
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
            print("✅ Message sent to \(session.connectedPeers.count) peers")
        } catch {
            print("❌ Error sending message: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Failed to send message - \(error.localizedDescription)"))
            }
        }
    }
    
    // MARK: - Message Persistence and Syncing
    
    // Save messages to UserDefaults
    private func saveMessages() {
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.messages)
            print("💾 Saved \(messages.count) messages to UserDefaults")
        } catch {
            print("❌ Failed to save messages: \(error.localizedDescription)")
        }
    }
    
    // Load messages from UserDefaults
    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.messages) else {
            print("ℹ️ No messages found in UserDefaults")
            return
        }
        
        do {
            let loadedMessages = try JSONDecoder().decode([ChatMessage].self, from: data)
            // Use main thread for UI updates
            DispatchQueue.main.async {
                self.messages = loadedMessages
                print("📂 Loaded \(loadedMessages.count) messages from UserDefaults")
            }
        } catch {
            print("❌ Failed to load messages: \(error.localizedDescription)")
        }
    }
    
    // Send all messages to a newly connected peer to sync histories
    private func syncMessages(with peerID: MCPeerID) {
        guard !messages.isEmpty else { return }
        
        do {
            // Create a special sync message that contains the entire message history
            let syncMessage = SyncMessage(messages: messages)
            let syncData = try JSONEncoder().encode(syncMessage)
            
            try session.send(syncData, toPeers: [peerID], with: .reliable)
            print("🔄 Sent message sync to \(peerID.displayName) with \(messages.count) messages")
        } catch {
            print("❌ Failed to sync messages: \(error.localizedDescription)")
        }
    }
    
    // Special message type for syncing
    struct SyncMessage: Codable {
        let type = "sync"
        let messages: [ChatMessage]
    }
    
    func disconnect() {
        print("🔌 Disconnecting from all peers")
        session.disconnect()
        stopHosting()
        stopBrowsing()
        
        // Clear all discovered peers
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll()
            self.messages.append(ChatMessage.systemMessage("Disconnected from all peers"))
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
                self.messages.append(ChatMessage.systemMessage("Connected to \(peerID.displayName)"))
                print("🔢 Total connected peers: \(session.connectedPeers.count)")
                print("📋 Connected peers list: \(session.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
                
                // Update peer state in discovered peers list
                self.updatePeerState(peerID, to: .connected)
                
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
                self.updatePeerState(peerID, to: .connecting)
                
            case .notConnected:
                print("❌ Disconnected from: \(peerID.displayName)")
                self.messages.append(ChatMessage.systemMessage("Disconnected from \(peerID.displayName)"))
                
                // If the peer exists in our discovered list, update its state,
                // otherwise it might have been removed already
                if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
                    self.discoveredPeers[index].state = .disconnected
                }
                
            @unknown default:
                print("❓ Unknown state (\(state.rawValue)) for: \(peerID.displayName)")
                self.messages.append(ChatMessage.systemMessage("Unknown connection state with \(peerID.displayName)"))
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("📥 Received data from: \(peerID.displayName) (\(data.count) bytes)")
        
        // 1. Try to decode as a SyncDecision first (highest priority)
        do {
            let syncDecision = try JSONDecoder().decode(SyncDecision.self, from: data)
            if syncDecision.type == "sync_decision" {
                print("🔄 Received sync decision from \(peerID.displayName): \(syncDecision.useRemote ? "they're using our history" : "they're keeping their history")")
                handleSyncDecision(theyUseRemote: syncDecision.useRemote, fromPeer: peerID)
                return
            }
        } catch {
            // Not a sync decision, continue
        }
        
        // 2. Try to decode as a SyncMessage
        do {
            let syncMessage = try JSONDecoder().decode(SyncMessage.self, from: data)
            if syncMessage.type == "sync" {
                print("🔄 Received sync message with \(syncMessage.messages.count) messages")
                handleMessageSync(messages: syncMessage.messages, fromPeer: peerID)
                return
            }
        } catch {
            // Not a sync message, continue with regular message handling
        }
        
        // 3. Try to decode the data as a regular ChatMessage
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
                self.messages = remoteMessages
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
        
        DispatchQueue.main.async {
            // If our history and their history are different in significant ways,
            // let the user decide which to keep
            let localOnlyMessages = self.messages.filter { localMsg in
                !syncedMessages.contains { $0.id == localMsg.id }
            }
            
            let remoteOnlyMessages = syncedMessages.filter { remoteMsg in
                !self.messages.contains { $0.id == remoteMsg.id }
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
        var newMessages = [ChatMessage]()
        
        // Add messages we don't already have
        for syncedMessage in syncedMessages {
            if !self.messages.contains(where: { $0.id == syncedMessage.id }) {
                newMessages.append(syncedMessage)
            }
        }
        
        // If we have new messages, add them and sort by timestamp
        if !newMessages.isEmpty {
            self.messages.append(contentsOf: newMessages)
            self.messages.sort(by: { $0.timestamp < $1.timestamp })
            print("✅ Added \(newMessages.count) new messages from sync")
            
            // Add a system message about the sync
            self.messages.append(ChatMessage.systemMessage("Synced \(newMessages.count) messages from \(peerID.displayName)"))
        } else {
            print("ℹ️ No new messages from sync")
        }
    }
    
    // Resolve message sync conflict by choosing either local or remote messages
    func resolveMessageSyncConflict(useRemote: Bool) {
        guard hasPendingSyncDecision, let peerID = pendingSyncPeer else {
            print("❌ No sync conflict to resolve")
            return
        }
        
        guard let remoteMessages = pendingSyncs[peerID] else {
            print("❌ Cannot find remote messages for \(peerID.displayName)")
            return
        }
        
        // First, send the decision to the other device
        sendSyncDecision(useRemote: useRemote, toPeer: peerID)
        
        // Then apply the decision locally
        applySyncDecision(useRemote: useRemote, peerID: peerID, remoteMessages: remoteMessages)
    }
    
    // Send the sync decision to the other device
    private func sendSyncDecision(useRemote: Bool, toPeer peerID: MCPeerID) {
        // Create a decision message
        // If we choose useRemote=true (we want to use their messages), we send "useRemote=true" 
        // so they know we're adopting their messages and they should keep their history
        // If we choose useRemote=false (we want to keep our messages), we send "useRemote=false"
        // so they know we're keeping our history and they should adopt our messages
        let decision = SyncDecision(useRemote: useRemote)
        
        do {
            let decisionData = try JSONEncoder().encode(decision)
            try session.send(decisionData, toPeers: [peerID], with: .reliable)
            print("📤 Sent sync decision (\(useRemote ? "use remote" : "keep local")) to \(peerID.displayName)")
        } catch {
            print("❌ Failed to send sync decision: \(error.localizedDescription)")
        }
    }
    
    // Apply the sync decision locally
    private func applySyncDecision(useRemote: Bool, peerID: MCPeerID, remoteMessages: [ChatMessage]) {
        if useRemote {
            // Replace our message history with the remote one
            print("🔄 Using remote message history from \(peerID.displayName)")
            DispatchQueue.main.async {
                self.messages = remoteMessages
                self.messages.append(ChatMessage.systemMessage("Adopted message history from \(peerID.displayName)"))
            }
        } else {
            // Keep our message history and add a system message
            print("🔄 Keeping local message history")
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Kept local message history"))
            }
        }
        
        // Clear the pending sync
        pendingSyncs.removeValue(forKey: peerID)
        pendingSyncPeer = nil
        hasPendingSyncDecision = false
    }
    
    // Special message type for sync decisions
    struct SyncDecision: Codable {
        let type = "sync_decision"
        let useRemote: Bool // true = sender is using receiver's history, false = sender is keeping their own history
    }
    
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
        
        // Only accept if not already connected
        guard !session.connectedPeers.contains(peerID) else {
            print("⚠️ Already connected to peer: \(peerID.displayName), declining invitation")
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Declining duplicate invitation from \(peerID.displayName)"))
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
            
            self.messages.append(ChatMessage.systemMessage("Received invitation from \(peerID.displayName)"))
            self.messages.append(ChatMessage.systemMessage("Waiting for you to accept or decline"))
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
                
                self.messages.append(ChatMessage.systemMessage("Discovered new peer \(peerID.displayName)"))
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
                    self.messages.append(ChatMessage.systemMessage("Lost sight of peer \(peerID.displayName)"))
                }
                
                // Remove any pending invitations
                self.pendingInvitations.removeValue(forKey: peerID)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Failed to start browsing: \(error.localizedDescription)")
        
        // Check if it's a MCError and provide more specific info
        let mcError = error as NSError
        if mcError.domain == MCErrorDomain {
            let errorType = MCError.Code(rawValue: mcError.code) ?? .unknown
            print("🔍 MultipeerConnectivity error: \(errorType)")
        }
        
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Failed to start browsing - \(error.localizedDescription)"))
            // Reset state
            self.isBrowsing = false
        }
    }
}