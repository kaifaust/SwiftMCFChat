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
            
            // Message list with improved styling and autoscroll
            ScrollViewReader { scrollView in
                List {
                    ForEach(Array(multipeerService.messages.enumerated()), id: \.element) { index, message in
                        HStack {
                            if message.starts(with: "System:") {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.gray)
                                
                                Text(message)
                                    .foregroundColor(.gray)
                                    .italic()
                                    .font(.footnote)
                            } else if message.starts(with: "Me:") {
                                Text(message)
                                    .foregroundColor(.blue)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                Text(message)
                                    .padding(6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .id(index)
                        .padding(.vertical, 2)
                    }
                    .onChange(of: multipeerService.messages.count) { _ in
                        if !multipeerService.messages.isEmpty {
                            withAnimation {
                                scrollView.scrollTo(multipeerService.messages.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
                .listStyle(.plain)
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
                
                // Connected peers with improved formatting and badge count
                if !multipeerService.connectedPeers.isEmpty {
                    HStack {
                        Image(systemName: multipeerService.connectedPeers.count > 1 ? "person.3.fill" : "person.fill")
                            .foregroundColor(.green)
                        
                        Text(multipeerService.connectedPeers.map { $0.displayName }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.trailing, 4)
                        
                        // Add badge with count
                        if multipeerService.connectedPeers.count > 0 {
                            Text("\(multipeerService.connectedPeers.count)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
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
