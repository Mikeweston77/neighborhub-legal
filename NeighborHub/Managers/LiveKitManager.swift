import Foundation
import SwiftUI
import Combine

#if canImport(LiveKit)
import LiveKit
#endif

@MainActor
final class LiveKitManager: ObservableObject {
    static let shared = LiveKitManager()

    @Published var isConnected = false
    @Published var isSpeaking = false
    @Published var activeSpeakers: Set<String> = []
    @Published var error: Error?

    #if canImport(LiveKit)
    private var room: Room?
    private var cancellables = Set<AnyCancellable>()
    #endif

    private init() {}

    func connect(url: String, token: String, completion: @escaping (Error?) -> Void) {
        #if canImport(LiveKit)
        disconnect()

        let room = Room()
        self.room = room

        room.add(delegate: self)

        Task {
            do {
                try await room.connect(url: url, token: token)
                DispatchQueue.main.async {
                    self.isConnected = true
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isConnected = false
                    completion(error)
                }
            }
        }
        #else
        completion(NSError(domain: "LiveKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "LiveKit is not available."]))
        #endif
    }

    func disconnect() {
        #if canImport(LiveKit)
        Task {
            if let room = room {
                await room.disconnect()
            }
            DispatchQueue.main.async {
                self.isConnected = false
                self.isSpeaking = false
                self.activeSpeakers.removeAll()
                self.room = nil
            }
        }
        #endif
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        #if canImport(LiveKit)
        guard let room = room, isConnected else { return }

        Task {
            do {
                try await room.localParticipant.setMicrophone(enabled: enabled)
                DispatchQueue.main.async {
                    self.isSpeaking = enabled
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                }
            }
        }
        #endif
    }
}

#if canImport(LiveKit)
extension LiveKitManager: RoomDelegate {
    func room(_ room: Room, participant: RemoteParticipant, didUpdate publication: TrackPublication, muted: Bool) {
        // Track muted state
    }

    func room(_ room: Room, participant: Participant, didUpdate speaking: Bool) {
        DispatchQueue.main.async {
            if speaking {
                self.activeSpeakers.insert(participant.identity?.stringValue ?? "")
            } else {
                self.activeSpeakers.remove(participant.identity?.stringValue ?? "")
            }
        }
    }
    
    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldValue: ConnectionState) {
        DispatchQueue.main.async {
            self.isConnected = connectionState == .connected
        }
    }
}
#endif
