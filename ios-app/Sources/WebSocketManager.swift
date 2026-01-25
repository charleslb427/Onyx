
import Foundation
import UserNotifications
import UIKit

class WebSocketManager: NSObject, URLSessionWebSocketDelegate {
    
    static let shared = WebSocketManager()
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private let serverURL = URL(string: "wss://votre-vps-ip:3000")! // À REMPLACER PAR VOTRE IP VPS
    
    override init() {
        super.init()
    }
    
    func connect() {
        guard !isConnected else { return }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        print("🔌 WebSocket: Connecting...")
        receiveMessage()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        print("🔌 WebSocket: Disconnected")
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingMessage(text)
                    }
                @unknown default:
                    break
                }
                // Keep listening (Recursion loops the listener)
                self.receiveMessage()
                
            case .failure(let error):
                print("❌ WebSocket Error: \(error)")
                self.isConnected = false
                // Reconnect strategy (Exponential backoff could be better, simplified here)
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    self.connect()
                }
            }
        }
    }
    
    private func handleIncomingMessage(_ text: String) {
        print("📩 WebSocket Received: \(text)")
        
        // Expected JSON Format: {"title": "Instagram", "body": "New Message"}
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        let title = json["title"] as? String ?? "Onyx"
        let body = json["body"] as? String ?? "Notification reçue"
        
        scheduleNotification(title: title, body: body)
    }
    
    private func scheduleNotification(title: String, body: String) {
        // Trigger generic Local Notification
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error displaying notification: \(error)")
            }
        }
    }
    
    // MARK: - URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket: Connected!")
        self.isConnected = true
        
        // Optional: Send Auth / Hello
        // let hello = "{\"type\":\"auth\", \"userId\":\"123\"}"
        // let message = URLSessionWebSocketTask.Message.string(hello)
        // webSocketTask.send(message) { _ in }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket: Closed by server")
        self.isConnected = false
        // Reconnect
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            self.connect()
        }
    }
}
