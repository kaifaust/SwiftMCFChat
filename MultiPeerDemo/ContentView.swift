//
//  ContentView.swift
//  MultiPeerDemo
//
//  Created by Kai on 3/17/25.
//

import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @StateObject private var multipeerService = MultipeerService()
    @State private var messageText = ""
    @State private var isConnecting = false
    
    var body: some View {
        VStack {
            // Header
            HStack {
                Text("MultipeerDemo")
                    .font(.headline)
                
                Spacer()
                
                // Connection status
                Text("\(multipeerService.connectedPeers.count) connected")
                    .font(.caption)
                    .foregroundColor(multipeerService.connectedPeers.isEmpty ? .red : .green)
            }
            .padding()
            
            // Message list
            List {
                ForEach(multipeerService.messages, id: \.self) { message in
                    Text(message)
                }
            }
            
            // Connection controls
            HStack {
                Button(isConnecting ? "Disconnect" : "Connect") {
                    isConnecting.toggle()
                    
                    if isConnecting {
                        multipeerService.startHosting()
                        multipeerService.startBrowsing()
                    } else {
                        multipeerService.stopHosting()
                        multipeerService.stopBrowsing()
                    }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                // Connected peers
                if !multipeerService.connectedPeers.isEmpty {
                    Text("Peers: " + multipeerService.connectedPeers.map { $0.displayName }.joined(separator: ", "))
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding()
            
            // Message input
            HStack {
                TextField("Type a message", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: {
                    guard !messageText.isEmpty else { return }
                    
                    multipeerService.sendMessage(messageText)
                    messageText = ""
                }) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(messageText.isEmpty || multipeerService.connectedPeers.isEmpty)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
