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
    
    // The local peer ID representing this device - now persistent across app launches
    let myPeerId: MCPeerID = {
        let defaults = UserDefaults.standard
        
        // Get the current device name to check for changes
        #if canImport(UIKit)
        let currentDisplayName = UIDevice.current.name
        #else
        let currentDisplayName = Host.current().localizedName ?? "Unknown Mac"
        #endif
        
        // Check for stored display name
        let oldDisplayName = defaults.string(forKey: UserDefaultsKeys.peerDisplayName)
        
        // If we have a previous name and it matches the current name, try to restore the peer ID
        if let oldDisplayName = oldDisplayName, oldDisplayName == currentDisplayName,
           let peerIDData = defaults.data(forKey: UserDefaultsKeys.peerID),
           let savedPeerID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: peerIDData) {
            
            print("📱 Loaded saved peer ID: \(savedPeerID.displayName)")
            return savedPeerID
        } else {
            // Create a new peer ID and save it
            #if canImport(UIKit)
            let newPeerId = MCPeerID(displayName: currentDisplayName)
            #else
            let newPeerId = MCPeerID(displayName: currentDisplayName)
            #endif
            
            // Archive the peer ID and save it along with the display name
            if let peerIDData = try? NSKeyedArchiver.archivedData(withRootObject: newPeerId, requiringSecureCoding: true) {
                defaults.set(peerIDData, forKey: UserDefaultsKeys.peerID)
                defaults.set(currentDisplayName, forKey: UserDefaultsKeys.peerDisplayName)
                print("📱 Created and saved new peer ID: \(newPeerId.displayName)")
            } else {
                print("⚠️ Failed to archive peer ID")
            }
            
            return newPeerId
        }
    }()
    
    // User identity that remains consistent across devices
    let userId: UUID
    private let userName = "Me" // The user is always displayed as "Me"
    
    // UserDefaults keys
    private enum UserDefaultsKeys {
        static let userId = "MultipeerDemo.userId"
        static let messages = "MultipeerDemo.messages"
        static let peerID = "MultipeerDemo.peerID"
        static let peerDisplayName = "MultipeerDemo.peerDisplayName"
        static let knownPeers = "MultipeerDemo.knownPeers"
        static let blockedPeers = "MultipeerDemo.blockedPeers"
        static let syncEnabledPeers = "MultipeerDemo.syncEnabledPeers"
    }
    
    // Service type should be a unique identifier, following Bonjour naming conventions:
    // 1-15 characters, lowercase letters, numbers, and hyphens (no adjacent hyphens)
    let serviceType = "multipdemo-chat"
    
    // Active session with other connected peers
    var session: MCSession
    
    // Advertiser lets others know we're available
    var advertiser: MCNearbyServiceAdvertiser
    
    // Browser to find other peers
    var browser: MCNearbyServiceBrowser
    
    // Helper property to access session's connected peers
    var sessionConnectedPeers: [MCPeerID] {
        return session.connectedPeers
    }
    
    // Track connected peers
    @Published var connectedPeers: [MCPeerID] = []
    
    // Track discovered peers and their states
    @Published var discoveredPeers: [PeerInfo] = []
    
    // Messages array with ChatMessage objects instead of strings
    @Published var messages: [ChatMessage] = [] {
        didSet {
            // Only save messages when actually changed (not during initial load)
            if !isInitialLoad {
                saveMessages()
            }
        }
    }
    
    // Flag to prevent saving during initial load
    var isInitialLoad = true
    
    // Track devices we're syncing with and their message histories
    var pendingSyncs: [MCPeerID: [ChatMessage]] = [:]
    
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
        var peerId: MCPeerID  // Changed from let to var so we can update it
        var state: PeerState
        var discoveryInfo: [String: String]?
        var isNearby: Bool = true // Default to true for newly discovered peers
        
        static func == (lhs: PeerInfo, rhs: PeerInfo) -> Bool {
            // If we have user IDs, compare those instead of peer IDs
            if let lhsUserId = lhs.discoveryInfo?["userId"],
               let rhsUserId = rhs.discoveryInfo?["userId"] {
                return lhsUserId == rhsUserId
            }
            // Fall back to comparing peer IDs if no user IDs are available
            return lhs.peerId == rhs.peerId
        }
    }
    
    // Enum to track peer states
    enum PeerState: String {
        case discovered = "Discovered"
        case connecting = "Connecting..."
        case connected = "Connected"
        case disconnected = "Not Connected" // Previously connected device that is now disconnected
        case invitationSent = "Invitation Sent"
        case invitationReceived = "Invitation Received"
        case rejected = "Invitation Declined"
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
        
        // Load saved data
        loadMessages()
        loadKnownPeers()
        loadBlockedPeers()
        loadSyncEnabledPeers()
        
        // Add message about initialized service
        DispatchQueue.main.async {
            self.messages.append(ChatMessage.systemMessage("Service initialized with ID \(self.myPeerId.displayName)"))
        }
        
        // App lifecycle notifications are handled in MultiPeerDemoApp.swift
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
        updatePeerState(peerInfo.peerId, to: .invitationSent, reason: "User initiated invitation")
        
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
        // The peer might not be in discoveredPeers when accepting from a proactive alert
        // so we'll proceed if there's a pending invitation handler
        
        // Check if invitation handler exists for this peer
        if let handler = pendingInvitations[peerInfo.peerId] {
            if accept {
                print("✅ Accepting invitation from: \(peerInfo.peerId.displayName)")
                updatePeerState(peerInfo.peerId, to: .connecting, reason: "Invitation accepted by user")
                
                DispatchQueue.main.async {
                    self.messages.append(ChatMessage.systemMessage("Accepting invitation from \(peerInfo.peerId.displayName)"))
                }
                
                // Accept the invitation
                handler(true, session)
            } else {
                print("❌ Declining invitation from: \(peerInfo.peerId.displayName)")
                updatePeerState(peerInfo.peerId, to: .rejected, reason: "Invitation declined by user")
                
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
    var pendingInvitations: [MCPeerID: (Bool, MCSession?) -> Void] = [:]
    
    // Delegate for handling invitations proactively
    var pendingInvitationHandler: ((MCPeerID, (Bool, MCSession?) -> Void) -> Void)?
    
    // Store known and blocked peers
    @Published var knownPeers: [KnownPeerInfo] = []
    @Published var blockedPeers: Set<String> = []
    @Published var syncEnabledPeers: Set<String> = []
    
    // Structure to track known peer information
    struct KnownPeerInfo: Identifiable, Codable, Equatable {
        // Using var instead of let for id to allow it to be decoded
        var id: UUID = UUID()
        let displayName: String
        let userId: String
        let lastSeen: Date
        var syncEnabled: Bool = false
        
        static func == (lhs: KnownPeerInfo, rhs: KnownPeerInfo) -> Bool {
            return lhs.userId == rhs.userId
        }
    }
    
    // Helper to update peer state in the discoveredPeers array
    func updatePeerState(_ peerId: MCPeerID, to state: PeerState, reason: String = "No reason provided") {
        DispatchQueue.main.async {
            let oldState: PeerState?
            
            if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerId }) {
                oldState = self.discoveredPeers[index].state
                let wasNearby = self.discoveredPeers[index].isNearby
                
                // Only log if state actually changed
                if oldState != state {
                    print("🔄 Peer state change: \(peerId.displayName) changed from \(oldState!.rawValue) to \(state.rawValue). Reason: \(reason)")
                    self.discoveredPeers[index].state = state
                    
                    // When changing to connecting or connected state, peer must be nearby
                    if state == .connecting || state == .connected {
                        if !wasNearby {
                            self.discoveredPeers[index].isNearby = true
                            print("📡 Marking peer as nearby due to connection state: \(peerId.displayName)")
                        }
                    }
                }
            } else {
                // Add the peer if it doesn't exist yet (for proactive approaches)
                oldState = nil
                
                // When adding a new peer with connecting or connected state, it's definitely nearby
                let isNearby = (state == .connecting || state == .connected)
                
                self.discoveredPeers.append(PeerInfo(
                    peerId: peerId,
                    state: state,
                    isNearby: isNearby
                ))
                
                print("➕ New peer added: \(peerId.displayName) with initial state \(state.rawValue). Reason: \(reason)")
                if isNearby {
                    print("📡 New peer marked as nearby due to connection state")
                }
            }
            
            // Log section placement information
            let userIdInfo = self.discoveredPeers.first(where: { $0.peerId == peerId })?.discoveryInfo?["userId"] ?? "unknown"
            let isSyncEnabled = userIdInfo != "unknown" && self.isSyncEnabled(for: userIdInfo)
            
            if state == .connected || isSyncEnabled {
                print("📱 Device placement: \(peerId.displayName) will appear in 'My Devices' section (connected: \(state == .connected), sync enabled: \(isSyncEnabled))")
            } else {
                print("📱 Device placement: \(peerId.displayName) will appear in 'Other Devices' section")
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
            // Prevent redundant saves when adding a single message
            let wasInitialLoad = self.isInitialLoad
            self.isInitialLoad = true
            
            self.messages.append(chatMessage)
            
            // Restore state and save manually
            self.isInitialLoad = wasInitialLoad
            if !self.isInitialLoad {
                self.saveMessages()
            }
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
                // Prevent redundant saves
                let wasInitialLoad = self.isInitialLoad
                self.isInitialLoad = true
                
                self.messages.append(ChatMessage.systemMessage("Failed to send message - \(error.localizedDescription)"))
                
                // Restore state and save manually
                self.isInitialLoad = wasInitialLoad
                if !self.isInitialLoad {
                    self.saveMessages()
                }
            }
        }
    }
    
    // MARK: - Persistence and Syncing
    
    // Save messages to UserDefaults
    func saveMessages() {
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
            isInitialLoad = false
            return
        }
        
        do {
            let loadedMessages = try JSONDecoder().decode([ChatMessage].self, from: data)
            // Use main thread for UI updates
            DispatchQueue.main.async {
                self.messages = loadedMessages
                print("📂 Loaded \(loadedMessages.count) messages from UserDefaults")
                // Set isInitialLoad to false after successfully loading messages
                self.isInitialLoad = false
            }
        } catch {
            print("❌ Failed to load messages: \(error.localizedDescription)")
            isInitialLoad = false
        }
    }
    
    // Save known peers to UserDefaults
    func saveKnownPeers() {
        do {
            let data = try JSONEncoder().encode(knownPeers)
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.knownPeers)
            print("💾 Saved \(knownPeers.count) known peers to UserDefaults")
        } catch {
            print("❌ Failed to save known peers: \(error.localizedDescription)")
        }
    }
    
    // Load known peers from UserDefaults
    private func loadKnownPeers() {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.knownPeers) else {
            print("ℹ️ No known peers found in UserDefaults")
            return
        }
        
        do {
            let loadedPeers = try JSONDecoder().decode([KnownPeerInfo].self, from: data)
            DispatchQueue.main.async {
                self.knownPeers = loadedPeers
                print("📂 Loaded \(loadedPeers.count) known peers from UserDefaults")
            }
        } catch {
            print("❌ Failed to load known peers: \(error.localizedDescription)")
        }
    }
    
    // Save blocked peers to UserDefaults
    private func saveBlockedPeers() {
        // Convert Set<String> to Array for encoding
        let blockedArray = Array(blockedPeers)
        UserDefaults.standard.set(blockedArray, forKey: UserDefaultsKeys.blockedPeers)
        print("💾 Saved \(blockedPeers.count) blocked peers to UserDefaults")
    }
    
    // Load blocked peers from UserDefaults
    private func loadBlockedPeers() {
        guard let blockedArray = UserDefaults.standard.array(forKey: UserDefaultsKeys.blockedPeers) as? [String] else {
            print("ℹ️ No blocked peers found in UserDefaults")
            return
        }
        
        DispatchQueue.main.async {
            self.blockedPeers = Set(blockedArray)
            print("📂 Loaded \(self.blockedPeers.count) blocked peers from UserDefaults")
        }
    }
    
    
    // Functions to manage sync-enabled peers
    
    // Save sync-enabled peers to UserDefaults
    func saveSyncEnabledPeers() {
        // Convert Set<String> to Array for storage
        let syncArray = Array(syncEnabledPeers)
        UserDefaults.standard.set(syncArray, forKey: UserDefaultsKeys.syncEnabledPeers)
        print("💾 Saved \(syncEnabledPeers.count) sync-enabled peers to UserDefaults")
    }
    
    // Load sync-enabled peers from UserDefaults
    private func loadSyncEnabledPeers() {
        guard let syncArray = UserDefaults.standard.array(forKey: UserDefaultsKeys.syncEnabledPeers) as? [String] else {
            print("ℹ️ No sync-enabled peers found in UserDefaults")
            return
        }
        
        DispatchQueue.main.async {
            self.syncEnabledPeers = Set(syncArray)
            
            // Update the sync status in knownPeers to match
            for userId in syncArray {
                if let index = self.knownPeers.firstIndex(where: { $0.userId == userId }) {
                    self.knownPeers[index].syncEnabled = true
                }
            }
            
            print("📂 Loaded \(self.syncEnabledPeers.count) sync-enabled peers from UserDefaults")
        }
    }
    
    // Toggle sync for a specific peer by userId
    func toggleSync(for userId: String) {
        DispatchQueue.main.async {
            let newSyncState: Bool
            
            if self.syncEnabledPeers.contains(userId) {
                // Disable sync
                self.syncEnabledPeers.remove(userId)
                newSyncState = false
                print("🔄 Disabled sync for user: \(userId)")
            } else {
                // Enable sync
                self.syncEnabledPeers.insert(userId)
                newSyncState = true
                print("🔄 Enabled sync for user: \(userId)")
            }
            
            // Update the syncEnabled flag in knownPeers
            if let index = self.knownPeers.firstIndex(where: { $0.userId == userId }) {
                self.knownPeers[index].syncEnabled = newSyncState
                self.saveKnownPeers()
            }
            
            self.saveSyncEnabledPeers()
            
            // Find any related discovered peers to log section change
            let affectedPeers = self.discoveredPeers.filter { peer in
                peer.discoveryInfo?["userId"] == userId
            }
            
            for peer in affectedPeers {
                if newSyncState {
                    if peer.state != .connected {
                        print("📱 Section change: \(peer.peerId.displayName) will move from 'Other Devices' to 'My Devices' section (reason: sync enabled)")
                    }
                } else {
                    if peer.state != .connected {
                        print("📱 Section change: \(peer.peerId.displayName) will move from 'My Devices' to 'Other Devices' section (reason: sync disabled)")
                    } else {
                        print("📱 No section change for \(peer.peerId.displayName) - remains in 'My Devices' (reason: still connected)")
                    }
                }
            }
            
            // Add system message
            let status = newSyncState ? "enabled" : "disabled"
            self.messages.append(ChatMessage.systemMessage("Sync \(status) for peer"))
        }
    }
    
    // Check if a device is sync-enabled
    func isSyncEnabled(for userId: String) -> Bool {
        return syncEnabledPeers.contains(userId)
    }
    
    // Update or add a known peer
    func updateKnownPeer(displayName: String, userId: String) {
        DispatchQueue.main.async {
            // Check if this peer is already known
            if let index = self.knownPeers.firstIndex(where: { $0.userId == userId }) {
                // Update existing entry with new display name and timestamp, preserving sync status
                var updatedPeer = KnownPeerInfo(
                    displayName: displayName,
                    userId: userId,
                    lastSeen: Date()
                )
                // Maintain existing sync status
                updatedPeer.syncEnabled = self.knownPeers[index].syncEnabled
                self.knownPeers[index] = updatedPeer
            } else {
                // Add new known peer (automatically enable sync for newly discovered peers)
                let newPeer = KnownPeerInfo(
                    displayName: displayName,
                    userId: userId,
                    lastSeen: Date(),
                    syncEnabled: true
                )
                self.knownPeers.append(newPeer)
                
                // Add to sync enabled peers Set
                self.syncEnabledPeers.insert(userId)
                self.saveSyncEnabledPeers()
            }
            
            self.saveKnownPeers()
        }
    }
    
    // Send all messages to a newly connected peer to sync histories
    func syncMessages(with peerID: MCPeerID) {
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
        var type = "sync"
        let messages: [ChatMessage]
    }
    
    func disconnect() {
        print("🔌 Disconnecting from all peers")
        session.disconnect()
        stopHosting()
        stopBrowsing()
        
        // When MCF is turned off, don't completely clear discovered peers
        // but update state for known peers
        DispatchQueue.main.async {
            // Make a temporary copy to avoid mutation during iteration
            let currentPeers = self.discoveredPeers
            
            // First mark all peers as disconnected and not nearby
            for peer in currentPeers {
                // Get the index in case the array is being modified by other operations
                if let index = self.discoveredPeers.firstIndex(where: { $0.id == peer.id }) {
                    // For connected and sync-enabled peers, set to disconnected
                    if peer.state == PeerState.connected || 
                       (peer.discoveryInfo?["userId"] != nil && 
                        self.syncEnabledPeers.contains(peer.discoveryInfo?["userId"] ?? "")) {
                        self.discoveredPeers[index].state = PeerState.disconnected
                        self.discoveredPeers[index].isNearby = false
                        print("🔌 Setting peer \(peer.peerId.displayName) to disconnected and not nearby")
                    } else if peer.state == PeerState.disconnected {
                        // Already disconnected peers just need to be marked as not nearby
                        self.discoveredPeers[index].isNearby = false
                        print("🔌 Setting disconnected peer \(peer.peerId.displayName) to not nearby")
                    } else {
                        // For non-connected, non-known peers, remove them
                        self.discoveredPeers.remove(at: index)
                        print("🔌 Removing transient peer: \(peer.peerId.displayName)")
                    }
                }
            }
            
            self.messages.append(ChatMessage.systemMessage("Disconnected from all peers"))
        }
        
        // Clear pending invitations
        pendingInvitations.removeAll()
    }
    
    // MARK: - Peer Management Functions
    
    /// Block a user by userId
    func blockUser(userId: String) {
        DispatchQueue.main.async {
            self.blockedPeers.insert(userId)
            print("🚫 Blocked user: \(userId)")
            self.messages.append(ChatMessage.systemMessage("Blocked peer"))
            
            // Disconnect from any connected peers with this userId
            self.disconnectBlockedUser(userId: userId)
            
            self.saveBlockedPeers()
        }
    }
    
    /// Unblock a user by userId
    func unblockUser(userId: String) {
        DispatchQueue.main.async {
            self.blockedPeers.remove(userId)
            print("✅ Unblocked user: \(userId)")
            self.messages.append(ChatMessage.systemMessage("Unblocked peer"))
            
            self.saveBlockedPeers()
        }
    }
    
    /// Check if a user is blocked
    func isUserBlocked(_ userId: String) -> Bool {
        return blockedPeers.contains(userId)
    }
    
    /// Check if we should auto-connect to a user
    func shouldAutoConnect(to userId: String) -> Bool {
        // Auto-connect only to mutual known peers (peers that are in knownPeers and have sync enabled)
        return !isUserBlocked(userId) && 
               knownPeers.contains(where: { $0.userId == userId }) && 
               syncEnabledPeers.contains(userId)
    }
    
    /// Forget a device - remove from known peers, sync-enabled peers, and optionally block
    func forgetDevice(userId: String, andBlock: Bool = false) {
        print("🧹 Forgetting device with userId: \(userId)")
        
        // Perform UI-related operations on the main thread
        DispatchQueue.main.async {
            // Send forget request to connected peers if possible
            // This will attempt to have the other device also forget us (best-effort)
            self.sendForgetRequest(forUserId: userId)
            
            // Remove from known peers
            self.knownPeers.removeAll { $0.userId == userId }
            
            // Remove from sync-enabled peers
            self.syncEnabledPeers.remove(userId)
            
            // Update discovered peers
            for index in (0..<self.discoveredPeers.count).reversed() {
                if self.discoveredPeers[index].discoveryInfo?["userId"] == userId {
                    let peer = self.discoveredPeers[index]
                    
                    if self.discoveredPeers[index].isNearby {
                        // If the peer is nearby, we update its state to "discovered" instead of
                        // removing it, so it will appear in the "Other Devices" section
                        self.discoveredPeers[index].state = PeerState.discovered
                        print("🔄 Peer \(peer.peerId.displayName) forgotten - moved to 'Other Devices' section")
                    } else {
                        // If not nearby, remove it completely
                        self.discoveredPeers.remove(at: index)
                        print("🔄 Peer \(peer.peerId.displayName) forgotten and removed (not nearby)")
                    }
                }
            }
            
            // Always disconnect active connections when forgetting
            self.disconnectUser(userId: userId)
            
            // Block if requested
            if andBlock {
                self.blockedPeers.insert(userId)
                // When blocking, always remove from discovered peers
                self.discoveredPeers.removeAll(where: { 
                    $0.discoveryInfo?["userId"] == userId 
                })
                print("🚫 User blocked: \(userId)")
            }
            
            // Save changes
            self.saveKnownPeers()
            self.saveSyncEnabledPeers()
            self.saveBlockedPeers()
            
            self.messages.append(ChatMessage.systemMessage(andBlock ? "Forgot and blocked device" : "Forgot device"))
        }
    }
    
    /// Disconnect from a specific user by ID
    private func disconnectUser(userId: String) {
        // Make sure we're on the main thread for all UI updates and property access
        DispatchQueue.main.async {
            // Find all connected peers with this userId
            let peersToDisconnect = self.discoveredPeers.filter { 
                $0.state == .connected && 
                $0.discoveryInfo?["userId"] == userId 
            }.map { $0.peerId }
            
            for peerId in peersToDisconnect {
                // We can't directly disconnect a specific peer in MCSession
                // So we'll need to create a new session without this peer
                print("❌ Disconnecting from user \(userId) on device \(peerId.displayName)")
            }
            
            // If we need to disconnect from specific peers but keep others connected,
            // we'd need to recreate the session and only invite the peers we want to keep
            if !peersToDisconnect.isEmpty {
                print("🔄 Recreating session to remove specific peers")
                
                // Store current browsing and hosting states
                let wasBrowsing = self.isBrowsing
                let wasHosting = self.isHosting
                
                // Stop current browsing and advertising
                if wasBrowsing {
                    self.stopBrowsing()
                }
                if wasHosting {
                    self.stopHosting()
                }
                
                // Disconnect current session
                self.session.disconnect() // This will disconnect all peers
                
                // Create a new session
                self.session = MCSession(
                    peer: self.myPeerId,
                    securityIdentity: nil,
                    encryptionPreference: .required
                )
                self.session.delegate = self
                
                // Update connection state for all peers and remove connected peers
                self.discoveredPeers.removeAll(where: { $0.state == .connected })
                self.connectedPeers = []
                
                // Restart browsing and advertising if they were active
                if wasBrowsing {
                    self.startBrowsing()
                }
                if wasHosting {
                    self.startHosting()
                }
            }
        }
    }
    
    /// Special case for disconnecting blocked users
    private func disconnectBlockedUser(userId: String) {
        disconnectUser(userId: userId)
    }
    
    /// Send a request to other devices to forget this device (best effort)
    private func sendForgetRequest(forUserId userId: String) {
        // Capture session to avoid potential threading issues
        let currentSession = self.session
        
        // Identify peers with the target userId
        let targetPeers = currentSession.connectedPeers.filter { peer in
            // Find the peer in our discoveredPeers list to get its userId
            if let index = discoveredPeers.firstIndex(where: { $0.peerId == peer }),
               let peerUserId = discoveredPeers[index].discoveryInfo?["userId"] {
                // Only target peers with the matching userId
                return peerUserId == userId
            }
            return false
        }
        
        do {
            // Create a forget request using our own userId, so the remote device 
            // knows which userId to forget (our userId, not its own)
            let forgetRequest = ForgetDeviceRequest(userId: self.userId.uuidString)
            let forgetData = try JSONEncoder().encode(forgetRequest)
            
            // Only attempt to send if we have matching peers
            if !targetPeers.isEmpty {
                try currentSession.send(forgetData, toPeers: targetPeers, with: .reliable)
                print("📤 Sent forget request for our userId to \(targetPeers.count) peers with userId \(userId)")
            } else {
                // Also try sending to all connected peers as a fallback
                if !currentSession.connectedPeers.isEmpty {
                    try currentSession.send(forgetData, toPeers: currentSession.connectedPeers, with: .reliable)
                    print("📤 Sent forget request for our userId to all \(currentSession.connectedPeers.count) connected peers (fallback)")
                } else {
                    print("ℹ️ No connected peers to send forget request to")
                }
            }
        } catch {
            print("❌ Failed to send forget request: \(error.localizedDescription)")
        }
    }
    
    /// Message type for forget device requests
    struct ForgetDeviceRequest: Codable {
        var type = "forget_device"
        let userId: String
    }
    
    // Clear all messages
    func clearAllMessages() {
        print("🧹 Clearing all messages")
        DispatchQueue.main.async {
            // Keep only a new system message and avoid redundant saves
            let wasInitialLoad = self.isInitialLoad
            self.isInitialLoad = true
            
            self.messages = [ChatMessage.systemMessage("Chat history cleared")]
            
            // Restore state and save manually
            self.isInitialLoad = wasInitialLoad
            if !self.isInitialLoad {
                self.saveMessages()
            }
        }
    }
}
