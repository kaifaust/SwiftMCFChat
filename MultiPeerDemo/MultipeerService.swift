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
    private let myPeerId: MCPeerID = {
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
            // Only save messages when actually changed (not during initial load)
            if !isInitialLoad {
                saveMessages()
            }
        }
    }
    
    // Flag to prevent saving during initial load
    private var isInitialLoad = true
    
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
    private var pendingInvitations: [MCPeerID: (Bool, MCSession?) -> Void] = [:]
    
    // Delegate for handling invitations proactively
    var pendingInvitationHandler: ((MCPeerID, (Bool, MCSession?) -> Void) -> Void)?
    
    // Store known and blocked peers
    @Published private(set) var knownPeers: [KnownPeerInfo] = []
    @Published private(set) var blockedPeers: Set<String> = []
    @Published private(set) var syncEnabledPeers: Set<String> = []
    
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
    private func updatePeerState(_ peerId: MCPeerID, to state: PeerState, reason: String = "No reason provided") {
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
    private func saveKnownPeers() {
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
    private func saveSyncEnabledPeers() {
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
    private func updateKnownPeer(displayName: String, userId: String) {
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
        
        // 1. Try to decode as a ForgetDeviceRequest (highest priority)
        do {
            let forgetRequest = try JSONDecoder().decode(ForgetDeviceRequest.self, from: data)
            if forgetRequest.type == "forget_device" {
                print("🧹 Received forget device request for userId: \(forgetRequest.userId)")
                handleForgetDeviceRequest(userId: forgetRequest.userId, fromPeer: peerID)
                return
            }
        } catch {
            // Not a forget device request, continue
        }
        
        // 2. Try to decode as a SyncDecision 
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
        
        // 3. Try to decode as a SyncMessage
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
        
        // 4. Try to decode the data as a regular ChatMessage
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
                self.saveMessages()
            }
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
            // Replace our user messages with the remote ones, but keep our system messages
            print("🔄 Using remote message history from \(peerID.displayName)")
            DispatchQueue.main.async {
                // Temporarily disable saving during batch operations
                let wasInitialLoad = self.isInitialLoad
                self.isInitialLoad = true
                
                // Keep only our system messages
                let ourSystemMessages = self.messages.filter { $0.isSystemMessage }
                
                // Get user messages from remote
                let remoteUserMessages = remoteMessages.filter { !$0.isSystemMessage }
                
                // Combine and sort
                self.messages = ourSystemMessages + remoteUserMessages
                self.messages.sort(by: { $0.timestamp < $1.timestamp })
                
                // Add info message
                self.messages.append(ChatMessage.systemMessage("Adopted message history from \(peerID.displayName)"))
                
                // Restore previous state and trigger a single save
                self.isInitialLoad = wasInitialLoad
                if !self.isInitialLoad {
                    self.saveMessages()
                }
            }
        } else {
            // Keep our message history and add a system message
            print("🔄 Keeping local message history")
            DispatchQueue.main.async {
                // Temporarily disable saving
                let wasInitialLoad = self.isInitialLoad
                self.isInitialLoad = true
                
                self.messages.append(ChatMessage.systemMessage("Kept local message history"))
                
                // Restore previous state and trigger a single save
                self.isInitialLoad = wasInitialLoad
                if !self.isInitialLoad {
                    self.saveMessages()
                }
            }
        }
        
        // Clear the pending sync
        pendingSyncs.removeValue(forKey: peerID)
        pendingSyncPeer = nil
        hasPendingSyncDecision = false
    }
    
    // Special message type for sync decisions
    struct SyncDecision: Codable {
        var type = "sync_decision"
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
    
    // MARK: - App State Handling
    
    // Call this method when app becomes active
    func handleAppDidBecomeActive() {
        print("🔄 App became active - resuming connections")
        
        // The framework automatically resumes advertising and browsing,
        // but we need to log our state to help with debugging
        
        // Log current state
        print("📊 Current state:")
        print("   isHosting: \(isHosting)")
        print("   isBrowsing: \(isBrowsing)") 
        print("   connectedPeers: \(session.connectedPeers.count)")
        print("   discoveredPeers: \(discoveredPeers.count)")
        
        // Session will have been disconnected when app was backgrounded
        // Log all our discovered peers
        print("📋 Current discovered peers after becoming active:")
        for (index, peer) in discoveredPeers.enumerated() {
            print("   \(index): \(peer.peerId.displayName), state: \(peer.state.rawValue), userId: \(peer.discoveryInfo?["userId"] ?? "unknown")")
        }
    }
    
    // Call this method when app enters background
    func handleAppDidEnterBackground() {
        print("⏸️ App entered background - framework will disconnect session")
        
        // Framework automatically stops advertising, browsing, and disconnects session
        // Just log our current state for debugging
        print("📊 State before backgrounding:")
        print("   isHosting: \(isHosting)")
        print("   isBrowsing: \(isBrowsing)")
        print("   connectedPeers: \(session.connectedPeers.count)")
        print("   discoveredPeers: \(discoveredPeers.count)")
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
        guard !session.connectedPeers.contains(peerID) else {
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
            updatePeerState(peerID, to: .connecting, reason: "Auto-accepting invitation from known peer")
            
            DispatchQueue.main.async {
                self.messages.append(ChatMessage.systemMessage("Auto-accepting invitation from known peer \(peerID.displayName)"))
            }
            
            // We MUST NOT store the invitation handler for auto-accepted invitations
            // Otherwise it will cause duplicate accept attempts
            
            // Accept the invitation
            invitationHandler(true, session)
            return
        }
        
        // For peers we don't auto-connect with, store the invitation handler for later use
        pendingInvitations[peerID] = invitationHandler
        
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

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("🔍 Found peer: \(peerID.displayName), info: \(info?.description ?? "none")")
        
        // Get app state information for diagnostics
        #if canImport(UIKit)
        let appStateString = UIApplication.shared.applicationState == .active ? "active" : 
                            UIApplication.shared.applicationState == .background ? "background" : "inactive"
        print("📱 App state when found peer: \(appStateString)")
        #endif
        
        // Get userId from discovery info if available
        let userId = info?["userId"]
        
        // Check if this peer is blocked
        if let userId = userId, isUserBlocked(userId) {
            print("🚫 Ignoring blocked peer: \(peerID.displayName) with userId \(userId)")
            return
        }
        
        // Only add to discoveredPeers if not already in the list and not connected
        DispatchQueue.main.async {
            // Check if already connected
            if self.session.connectedPeers.contains(peerID) {
                print("⚠️ Peer already connected: \(peerID.displayName)")
                return
            }
            
            // Check if this is a known peer
            let isKnownPeer = userId != nil && self.knownPeers.contains(where: { $0.userId == userId })
            print("ℹ️ Found peer: \(peerID.displayName), isKnown: \(isKnownPeer ? "Yes" : "No")")
            
            // Check if already in discovered list
            if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
                // Always update discovery info
                let oldInfo = self.discoveredPeers[index].discoveryInfo
                self.discoveredPeers[index].discoveryInfo = info
                
                // Always mark as nearby when found
                self.discoveredPeers[index].isNearby = true
                
                print("🔄 Updated discovery info for existing peer: \(peerID.displayName)")
                print("   Old info: \(oldInfo?.description ?? "none")")
                print("   New info: \(info?.description ?? "none")")
                
                if self.discoveredPeers[index].state == .disconnected {
                    print("🔍 Disconnected peer is now nearby: \(peerID.displayName)")
                    
                    // Check if this is a peer we should auto-connect to
                    if let userId = userId, self.shouldAutoConnect(to: userId) {
                        print("🤝 Auto-connecting to previously known peer that is now nearby: \(peerID.displayName)")
                        self.invitePeer(self.discoveredPeers[index])
                    }
                }
            } else {
                // Before adding a new peer, check if we already know this user ID from another peer
                // This handles the case where the app restarts and rediscovers a known peer with a new peerID object
                var existingUserIdPeerIndex: Int? = nil
                
                if let userId = userId {
                    existingUserIdPeerIndex = self.discoveredPeers.firstIndex(where: { 
                        $0.discoveryInfo?["userId"] == userId 
                    })
                }
                
                if let existingIndex = existingUserIdPeerIndex, isKnownPeer {
                    // We already have a peer with this userId, update it instead of adding a new one
                    print("🔄 Found peer with existing userId: \(userId ?? "unknown"), updating instead of adding new")
                    
                    // Store the current state before updating
                    let currentState = self.discoveredPeers[existingIndex].state
                    
                    // Update the existing peer with new peerID but maintain state if disconnected
                    let updatedState = (currentState == PeerState.disconnected) ? PeerState.disconnected : PeerState.discovered
                    self.discoveredPeers[existingIndex].peerId = peerID
                    self.discoveredPeers[existingIndex].discoveryInfo = info
                    self.discoveredPeers[existingIndex].state = updatedState
                    self.discoveredPeers[existingIndex].isNearby = true
                    
                    print("🔄 Updated existing peer with userId \(userId ?? "unknown") to state: \(updatedState.rawValue)")
                    
                    // If this is a peer we should auto-connect to and was previously disconnected
                    if updatedState == .disconnected, let userId = userId, self.shouldAutoConnect(to: userId) {
                        print("🤝 Auto-connecting to previously known peer with new peerID: \(peerID.displayName)")
                        self.invitePeer(self.discoveredPeers[existingIndex])
                    }
                } else {
                    // Add new peer to discovered list
                    let initialState: PeerState = isKnownPeer ? PeerState.disconnected : PeerState.discovered
                    let newPeerInfo = PeerInfo(
                        peerId: peerID,
                        state: initialState,
                        discoveryInfo: info,
                        isNearby: true
                    )
                    self.discoveredPeers.append(newPeerInfo)
                    
                    print("➕ Added new peer to discovered list: \(peerID.displayName) with state: \(initialState.rawValue)")
                    self.messages.append(ChatMessage.systemMessage("Discovered new peer \(peerID.displayName)"))
                    
                    // If this is a known peer with disconnected state, check if we should auto-connect
                    if initialState == .disconnected, let userId = userId, self.shouldAutoConnect(to: userId) {
                        print("🤝 Auto-connecting to newly added known peer: \(peerID.displayName)")
                        self.invitePeer(newPeerInfo)
                    }
                }
                
                // If this is a known peer, update the last seen time
                if let userId = userId, isKnownPeer {
                    print("📝 Updating last seen time for known peer: \(peerID.displayName)")
                    self.updateKnownPeer(displayName: peerID.displayName, userId: userId)
                }
            }
            
            // Log current content of discoveredPeers
            print("📋 Current discovered peers list:")
            for (index, peer) in self.discoveredPeers.enumerated() {
                print("   \(index): \(peer.peerId.displayName), state: \(peer.state.rawValue), userId: \(peer.discoveryInfo?["userId"] ?? "unknown")")
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
        
        // Get app state information for diagnostics
        #if canImport(UIKit)
        let appStateString = UIApplication.shared.applicationState == .active ? "active" : 
                            UIApplication.shared.applicationState == .background ? "background" : "inactive"
        print("📱 App state when lost peer: \(appStateString)")
        #endif
        
        DispatchQueue.main.async {
            // If the peer is in our discovered list
            if let index = self.discoveredPeers.firstIndex(where: { $0.peerId == peerID }) {
                let currentState = self.discoveredPeers[index].state
                let userId = self.discoveredPeers[index].discoveryInfo?["userId"]
                
                // When a peer is lost, it's definitely not nearby anymore
                self.discoveredPeers[index].isNearby = false
                print("📡 Marking peer as not nearby: \(peerID.displayName)")
                
                // Log info about the lost peer to help understand why it's being removed
                print("ℹ️ Lost peer details: peerID=\(peerID.displayName), state=\(currentState.rawValue), userId=\(userId ?? "unknown")")
                print("ℹ️ Connected peers count: \(self.session.connectedPeers.count)")
                print("ℹ️ Is known peer? \(userId != nil && self.knownPeers.contains(where: { $0.userId == userId }) ? "Yes" : "No")")
                print("ℹ️ Is sync enabled? \(userId != nil && self.syncEnabledPeers.contains(userId!) ? "Yes" : "No")")
                
                // Special handling based on current peer state
                switch currentState {
                case .connected:
                    // For connected peers, we should KEEP them in the discovered list so they can appear in
                    // the UI with the appropriate state. The session delegate will properly handle
                    // disconnection when it receives the state change notification.
                    // 
                    // This is critical for backgrounded devices since we need to maintain UI awareness of the peer
                    // and be ready for when they return to foreground.
                    print("ℹ️ Keeping connected peer that was lost: \(peerID.displayName)")
                    // Update message only if peer is not actually still connected (could be app state changes)
                    if !self.session.connectedPeers.contains(peerID) {
                        print("🔄 Peer no longer appears in session's connected peers list")
                        self.messages.append(ChatMessage.systemMessage("Lost connection to \(peerID.displayName)"))
                    } else {
                        print("ℹ️ Peer still appears in session's connected peers list - keeping without changes")
                    }
                    
                case .disconnected:
                    // Keep disconnected peers in the list but mark as not nearby
                    self.discoveredPeers[index].isNearby = false
                    print("🔄 Keeping disconnected peer in the list: \(peerID.displayName) (marked as not nearby)")
                    
                case .rejected:
                    // If rejected, keep it in the list 
                    // (important for retrying connections)
                    print("🔄 Keeping rejected peer in the list: \(peerID.displayName)")
                    
                case .discovered:
                    // For discovered peers, if they're known or sync-enabled, mark as disconnected
                    if let userId = userId,
                       self.knownPeers.contains(where: { $0.userId == userId }) || 
                       self.syncEnabledPeers.contains(userId) {
                        self.discoveredPeers[index].state = PeerState.disconnected
                        self.discoveredPeers[index].isNearby = false
                        print("🔄 Changing discovered peer to disconnected state: \(peerID.displayName)")
                    } else {
                        // Only remove unknown discovered peers
                        print("🔄 Removing unknown discovered peer: \(peerID.displayName)")
                        self.discoveredPeers.remove(at: index)
                    }
                    
                case .connecting, .invitationSent, .invitationReceived:
                    // For transient states, only remove if not in session.connectedPeers
                    if !self.session.connectedPeers.contains(peerID) {
                        // Check if this is a known peer we should keep
                        if let userId = userId,
                           (self.knownPeers.contains(where: { $0.userId == userId }) || 
                            self.syncEnabledPeers.contains(userId)) {
                            // For known peers, mark as disconnected when lost
                            self.discoveredPeers[index].state = PeerState.disconnected
                            self.discoveredPeers[index].isNearby = false
                            print("🔄 Changing transient state peer to disconnected state: \(peerID.displayName)")
                        } else {
                            // Unknown peer in transient state, safe to remove
                            print("🔄 Removing unknown peer: \(peerID.displayName) (not in known peers list)")
                            self.discoveredPeers.remove(at: index)
                            self.messages.append(ChatMessage.systemMessage("Lost sight of peer \(peerID.displayName)"))
                        }
                    } else {
                        print("⚠️ Peer not in session's connected peers but keeping it: \(peerID.displayName)")
                    }
                }
            } else {
                print("ℹ️ Lost peer not found in discoveredPeers: \(peerID.displayName)")
            }
            
            // Remove any pending invitations
            self.pendingInvitations.removeValue(forKey: peerID)
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