import SwiftUI

/// Grid of event profiles with active indicator, create/edit/delete.
///
/// Shown inside the settings sheet as the "Events" tab.
struct ProfileListView: View {

    @EnvironmentObject var profileManager: EventProfileManager
    @State private var showEditor = false
    @State private var editingProfile: EventProfile?
    @State private var showDeleteAlert = false
    @State private var profileToDelete: EventProfile?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(profileManager.profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        isActive: profile.id == profileManager.activeProfile.id,
                        onActivate: { profileManager.activateProfile(profile) },
                        onEdit: {
                            editingProfile = profile
                            showEditor = true
                        },
                        onDuplicate: { _ = profileManager.duplicateProfile(profile) },
                        onDelete: {
                            profileToDelete = profile
                            showDeleteAlert = true
                        }
                    )
                }

                // Add new profile button
                Button(action: createNewProfile) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.cyan.opacity(0.6))
                        Text("New Profile")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [6]))
                    )
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showEditor) {
            if let profile = editingProfile {
                ProfileEditorView(profile: profile)
            }
        }
        .alert("Delete Profile?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    profileManager.deleteProfile(profile)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let profile = profileToDelete {
                Text("Delete \"\(profile.name)\"? This cannot be undone.")
            }
        }
    }

    private func createNewProfile() {
        let profile = profileManager.createProfile(name: "New Event")
        editingProfile = profile
        showEditor = true
    }
}

// MARK: - Profile Card

private struct ProfileCard: View {

    let profile: EventProfile
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onActivate) {
            VStack(alignment: .leading, spacing: 8) {
                // Color swatch + name
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(UIColor(hex: profile.branding.primaryColorHex) ?? .cyan))
                        .frame(width: 16, height: 16)

                    Text(profile.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }

                // Branding preview
                Text(profile.branding.title)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)

                // Config summary
                HStack(spacing: 6) {
                    Label(profile.config.captureMode.displayName, systemImage: captureIcon)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                    Label(profile.config.layoutMode.rawValue.capitalized, systemImage: "rectangle.grid.1x2")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }

                if profile.isDefault {
                    Text("Built-in")
                        .font(.caption2)
                        .foregroundColor(.yellow.opacity(0.5))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 100)
            .background(isActive ? Color.cyan.opacity(0.1) : Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.cyan.opacity(0.6) : Color.white.opacity(0.1), lineWidth: isActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            if !profile.isDefault {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var captureIcon: String {
        switch profile.config.captureMode {
        case .photo: return "camera"
        case .boomerangGIF: return "arrow.2.squarepath"
        case .burstGIF: return "photo.stack"
        }
    }
}
