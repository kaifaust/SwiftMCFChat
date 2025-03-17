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
    @State private var showInfoAlert = false
    
    var body: some View {
        VStack {
            // Header with more status information
            HStack {
                Text("MultipeerDemo")
                    .font(.headline)
                
                Spacer()
                
                // Connection status with more details
                HStack {
                    Circle()
                        .fill(multipeerService.connectedPeers.isEmpty ? .red : .green)
                        .frame(width: 10, height: 10)
                    
                    Text("\(multipeerService.connectedPeers.count) connected")
                        .font(.caption)
                    
                    if isConnecting {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                    }
                }
                
                Button(action: {
                    showInfoAlert = true
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
                .alert("Connection Information", isPresented: $showInfoAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Hosting: \(multipeerService.isHosting ? "Yes" : "No")\nBrowsing: \(multipeerService.isBrowsing ? "Yes" : "No")\nPeers: \(multipeerService.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
                }
            }
            .padding()
            
            // Message list with autoscroll
            ScrollViewReader { scrollView in
                List {
                    ForEach(Array(multipeerService.messages.enumerated()), id: \.element) { index, message in
                        Text(message)
                            .padding(4)
                            .id(index)
                            .background(message.starts(with: "System:") ? Color.gray.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                    }
                    .onChange(of: multipeerService.messages.count) { _ in
                        if !multipeerService.messages.isEmpty {
                            scrollView.scrollTo(multipeerService.messages.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Connection controls
            HStack {
                Button(action: {
                    isConnecting.toggle()
                    
                    if isConnecting {
                        multipeerService.startHosting()
                        multipeerService.startBrowsing()
                    } else {
                        multipeerService.disconnect()
                    }
                }) {
                    HStack {
                        Image(systemName: isConnecting ? "network.slash" : "network")
                        Text(isConnecting ? "Disconnect" : "Connect")
                    }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                // Connected peers with better formatting
                if !multipeerService.connectedPeers.isEmpty {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.green)
                        
                        Text(multipeerService.connectedPeers.map { $0.displayName }.joined(separator: ", "))
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding()
            
            // Message input with improved UI
            HStack {
                TextField("Type a message", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(messageText.isEmpty || multipeerService.connectedPeers.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty || multipeerService.connectedPeers.isEmpty)
            }
            .padding()
        }
        .onAppear {
            multipeerService.messages.append("System: Welcome to MultipeerDemo")
            multipeerService.messages.append("System: Click Connect to start")
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        multipeerService.sendMessage(messageText)
        messageText = ""
    }
}

#Preview {
    ContentView()
}
