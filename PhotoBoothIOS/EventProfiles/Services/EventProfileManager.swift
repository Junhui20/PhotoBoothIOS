import Combine
import Foundation
import os

/// Manages event profile CRUD, persistence, and activation.
///
/// Storage: `Documents/EventProfiles/profiles.json`
///
/// Thread model matches `GalleryStore`:
/// - `@Published` properties on MainActor
/// - File I/O via `Task.detached`
/// - `nonisolated` path helpers
/// - Atomic JSON writes (temp → rename)
final class EventProfileManager: ObservableObject {

    // MARK: - Published

    @Published var profiles: [EventProfile] = []
    @Published var activeProfile: EventProfile = EventProfile.defaults[0]

    // MARK: - Private

    private nonisolated let logger = Logger(
        subsystem: "com.photobooth.profiles", category: "EventProfileManager"
    )

    private nonisolated static let activeIDKey = "activeEventProfileID"

    // MARK: - Shared Encoder/Decoder

    private nonisolated static let sharedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private nonisolated static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Paths (nonisolated — FileManager is thread-safe)

    private nonisolated var profilesRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("EventProfiles", isDirectory: true)
    }

    private nonisolated var indexFileURL: URL {
        profilesRoot.appendingPathComponent("profiles.json")
    }

    // MARK: - Init

    init() {
        ensureDirectories()
    }

    // MARK: - Load

    /// Load profiles from disk. Creates defaults on first launch.
    func loadProfiles() {
        Task.detached { [weak self] in
            guard let self else { return }

            var loaded: [EventProfile] = []

            do {
                let data = try Data(contentsOf: self.indexFileURL)
                loaded = try Self.sharedDecoder.decode([EventProfile].self, from: data)
                self.logger.info("Loaded \(loaded.count) profiles from disk")
            } catch {
                self.logger.info("No profiles found (first launch): \(error.localizedDescription)")
            }

            // Seed defaults if empty
            if loaded.isEmpty {
                loaded = EventProfile.defaults
                Self.writeIndexToDisk(
                    profiles: loaded,
                    indexURL: self.indexFileURL,
                    profilesDir: self.profilesRoot
                )
                self.logger.info("Created \(loaded.count) default profiles")
            }

            // Resolve active profile
            let savedActiveID = UserDefaults.standard.string(forKey: Self.activeIDKey)
                .flatMap { UUID(uuidString: $0) }
            let active = loaded.first(where: { $0.id == savedActiveID }) ?? loaded[0]

            await MainActor.run {
                self.profiles = loaded
                self.activeProfile = active
            }
        }
    }

    // MARK: - CRUD

    /// Create a new profile with default settings.
    func createProfile(name: String) -> EventProfile {
        let profile = EventProfile(name: name)
        var updated = profiles
        updated.append(profile)
        profiles = updated
        persistIndex(updated)
        logger.info("Created profile: \(name)")
        return profile
    }

    /// Update an existing profile in place.
    func updateProfile(_ profile: EventProfile) {
        var updated = profiles
        guard let index = updated.firstIndex(where: { $0.id == profile.id }) else { return }

        var modified = profile
        modified.updatedAt = .now
        updated[index] = modified
        profiles = updated

        // If this is the active profile, update active too
        if activeProfile.id == profile.id {
            activeProfile = modified
        }

        persistIndex(updated)
        logger.info("Updated profile: \(profile.name)")
    }

    /// Delete a profile. Built-in profiles cannot be deleted.
    func deleteProfile(_ profile: EventProfile) {
        guard !profile.isDefault else {
            logger.warning("Cannot delete default profile: \(profile.name)")
            return
        }

        var updated = profiles
        updated.removeAll { $0.id == profile.id }
        profiles = updated

        // If deleted the active profile, switch to first
        if activeProfile.id == profile.id, let first = updated.first {
            activateProfile(first)
        }

        persistIndex(updated)
        logger.info("Deleted profile: \(profile.name)")
    }

    /// Duplicate a profile with a new UUID and " Copy" suffix.
    func duplicateProfile(_ profile: EventProfile) -> EventProfile {
        let copy = EventProfile(
            name: profile.name + " Copy",
            branding: profile.branding,
            config: profile.config,
            isDefault: false
        )

        var updated = profiles
        updated.append(copy)
        profiles = updated
        persistIndex(updated)
        logger.info("Duplicated profile: \(profile.name) → \(copy.name)")
        return copy
    }

    // MARK: - Activation

    /// Set the active profile. Persists active ID to UserDefaults.
    func activateProfile(_ profile: EventProfile) {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        activeProfile = profile
        UserDefaults.standard.set(profile.id.uuidString, forKey: Self.activeIDKey)
        logger.info("Activated profile: \(profile.name)")
    }

    // MARK: - Private Helpers

    private func ensureDirectories() {
        do {
            try FileManager.default.createDirectory(
                at: profilesRoot, withIntermediateDirectories: true
            )
        } catch {
            logger.error("Failed to create profiles directory: \(error)")
        }
    }

    /// Persist the current profiles list to disk (background).
    private func persistIndex(_ profiles: [EventProfile]) {
        let indexURL = indexFileURL
        let dir = profilesRoot
        Task.detached {
            Self.writeIndexToDisk(profiles: profiles, indexURL: indexURL, profilesDir: dir)
        }
    }

    /// Atomically write profiles JSON to disk (temp → rename).
    private nonisolated static func writeIndexToDisk(
        profiles: [EventProfile],
        indexURL: URL,
        profilesDir: URL
    ) {
        do {
            let data = try sharedEncoder.encode(profiles)
            let tempURL = profilesDir.appendingPathComponent("profiles.tmp.json")
            try data.write(to: tempURL, options: .atomic)

            if FileManager.default.fileExists(atPath: indexURL.path) {
                try FileManager.default.removeItem(at: indexURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: indexURL)
        } catch {
            Logger(subsystem: "com.photobooth.profiles", category: "EventProfileManager")
                .error("Failed to write profiles index: \(error)")
        }
    }
}
