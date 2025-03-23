//
//  PeerRowView.swift
//  MultiPeerDemo
//
//  Created by Claude on 3/18/25.
//

import SwiftUI
import MultipeerConnectivity

// PeerRowView with simplified UI
struct PeerRowView: View {
    let peer: MultipeerService.PeerInfo
    let action: () -> Void
    let onForget: () -> Void
    let onBlock: () -> Void
    @EnvironmentObject var multipeerService: MultipeerService
    
    var body: some View {
        HStack {
            // Main content - this part will be clickable for "discovered" peers
            HStack {
                // Peer icon
                Image(systemName: iconForState(peer.state))
                    .font(.system(size: 18))
                    .foregroundColor(colorForState(peer.state))
                    .frame(width: 32, height: 32)
                    .background(colorForState(peer.state).opacity(0.2))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    // Peer name
                    Text(peer.peerId.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    // Peer state
                    HStack(spacing: 4) {
                        // Show status with nearby information for disconnected peers
                        if peer.state == .disconnected {
                            if peer.isNearby {
                                Text("Not Connected, Nearby")
                                    .font(.caption)
                                    .foregroundColor(colorForState(peer.state))
                            } else {
                                Text("Not Connected")
                                    .font(.caption)
                                    .foregroundColor(Color.gray)
                            }
                        } else {
                            Text(peer.state.rawValue)
                                .font(.caption)
                                .foregroundColor(colorForState(peer.state))
                        }
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle()) // Make the entire area tappable
            .onTapGesture {
                if isActionable(peer.state) {
                    action()
                }
            }
            
            // Action buttons - these remain independently clickable
            HStack(spacing: 8) {
                // Show Forget button for connected peers or sync-enabled peers
                if peer.state == .connected || 
                   (peer.discoveryInfo?["userId"] != nil && 
                    multipeerService.isSyncEnabled(for: peer.discoveryInfo?["userId"] ?? "")) {
                    // Forget button
                    Button(action: onForget) {
                        Text("Forget")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                
                // Block button - show for all peers
                Button(action: onBlock) {
                    Text("Block")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isActionable(peer.state) ? colorForState(peer.state).opacity(0.3) : Color.secondary.opacity(0.3), 
                    lineWidth: isActionable(peer.state) ? 1.5 : 1
                )
        )
        .opacity(isActionable(peer.state) ? 1.0 : 0.85)
    }
    
    // Determine if peer state is actionable (can be tapped to connect)
    private func isActionable(_ state: MultipeerService.PeerState) -> Bool {
        // Discovered, disconnected and rejected peers can be tapped to connect/retry
        return state == .discovered || state == .rejected || state == .disconnected
        // We don't make invitationSent peers actionable since clicking again would be redundant
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
            // Use different icons based on whether peer is nearby or not
            return peer.isNearby ? "person.crop.circle.badge.clock" : "person.crop.circle.badge.xmark"
        case .invitationSent:
            return "envelope"
        case .rejected:
            return "xmark.circle"
        default:
            return "person.crop.circle.badge.questionmark"
        }
    }
    
    // Get appropriate color for peer state
    private func colorForState(_ state: MultipeerService.PeerState) -> Color {
        return getStateColor(state)
    }
    
    // Helper to avoid complex type-checking
    private func getStateColor(_ state: MultipeerService.PeerState) -> Color {
        switch state {
        case .discovered:
            return .blue
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .disconnected:
            // Use a more muted color for disconnected peers
            return .gray.opacity(0.8)
        case .invitationSent:
            return .purple
        case .rejected:
            return .orange
        default:
            return .gray
        }
    }
}
