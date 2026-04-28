import SwiftUI
import PhotosUI

struct EditProfileSheet: View {
    @Environment(SocialDataService.self) private var social
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var handle: String = ""
    @State private var bio: String = ""
    @State private var location: String = ""
    @State private var pronouns: String = ""
    @State private var website: String = ""
    @State private var avatarTone: AvatarTone = .sunset
    @State private var bannerTone: AvatarTone = .sunset
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var clearPhoto: Bool = false
    /// R2 key returned by POST /v1/media/avatar after a successful
    /// upload. Persisted on save so the backend stores it on the
    /// athlete row + serves it to any device. `clearPhoto` with this
    /// nil wipes the remote avatar.
    @State private var uploadedAvatarKey: String?
    @State private var isUploading: Bool = false
    @State private var uploadError: String?
    @State private var isSaving: Bool = false
    @State private var showcase: [UUID] = []
    @State private var showcasePicker = false

    /// Simple URL validity check matching the server's rule:
    /// non-empty must parse through URL(string:) + have a scheme.
    private var websiteValid: Bool {
        let v = website.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return true }
        guard let url = URL(string: v), let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Matches the server's Zod constraint (`/^[a-z0-9_]{2,24}$/`).
    /// Rendered inline under the handle field, and gates Save.
    private var handleValid: Bool {
        let trimmed = handle.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.count <= 24 else { return false }
        return trimmed.allSatisfy { $0.isLetter && $0.isLowercase || $0.isNumber || $0 == "_" }
    }

    /// Name is required (any non-whitespace); handle must be valid;
    /// website must parse if non-empty. Photo upload in flight also
    /// blocks save so we never drop the user's new avatar.
    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && handleValid
            && websiteValid
            && !isUploading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.lg) {
                    avatarBlock
                    tonesBlock
                    fieldsBlock
                    showcaseBlock
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showcasePicker) {
                ShowcasePickerSheet(selected: $showcase)
                    .presentationDetents([.large])
                    .presentationCornerRadius(Theme.Radius.xl)
            }
            .alert("Couldn't upload photo",
                   isPresented: Binding(
                       get: { uploadError != nil },
                       set: { if !$0 { uploadError = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadError ?? "")
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) {
                Task { await loadPhoto() }
            }
        }
    }

    // MARK: - Avatar

    private var avatarBlock: some View {
        VStack(spacing: 14) {
            // Mirror the live profile layout: a banner strip on top,
            // avatar overlapping the bottom edge. Each picker now has
            // an unmistakable visible target — earlier the bannerTone
            // showed only as a blurred glow behind the avatar, which
            // users read as the avatar's own gradient.
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(bannerTone.gradient)
                    .frame(height: 96)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.0), .black.opacity(0.22)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg,
                                                    style: .continuous))
                    )
                ZStack {
                    // Glow halo that uses avatarTone — same color as
                    // the ring so it unmistakably belongs to the
                    // avatar (not the banner). Brings back the
                    // gradient-glow vibe people loved.
                    Circle()
                        .fill(avatarTone.gradient)
                        .frame(width: 144, height: 144)
                        .opacity(0.55)
                        .blur(radius: 22)
                    previewAvatar
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                    // Avatar tone also renders as the ring so the
                    // picker has clear feedback even when a photo
                    // overrides the fill inside the circle.
                    Circle()
                        .strokeBorder(avatarTone.gradient, lineWidth: 4)
                        .frame(width: 96, height: 96)
                    if isUploading {
                        Circle()
                            .fill(.black.opacity(0.4))
                            .frame(width: 96, height: 96)
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                }
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
                .offset(y: 36)
            }
            .padding(.bottom, 40)

            HStack(spacing: 8) {
                let hasPhoto = photoData != nil || (!clearPhoto && social.me?.photoData != nil)
                PhotosPicker(selection: $photoItem, matching: .images,
                             photoLibrary: .shared()) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.fill").font(.system(size: 13, weight: .bold))
                        Text(hasPhoto ? "Change photo" : "Upload photo")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.Color.inkInverse)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.Color.ink))
                }
                if hasPhoto {
                    Button {
                        Haptics.tap()
                        photoData = nil
                        photoItem = nil
                        clearPhoto = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash").font(.system(size: 12, weight: .bold))
                            Text("Remove")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Theme.Color.inkSoft)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.Color.bgElevated))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.md)
    }

    @ViewBuilder
    private var previewAvatar: some View {
        if !clearPhoto, let data = photoData ?? social.me?.photoData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                avatarTone.gradient
                let initials = displayName.split(separator: " ").prefix(2)
                    .compactMap { $0.first }.map(String.init).joined().uppercased()
                Text(initials.isEmpty ? "YOU" : initials)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
        }
    }

    // MARK: - Tones

    private var tonesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            toneGroup(title: "Avatar gradient", selected: $avatarTone)
            toneGroup(title: "Banner", selected: $bannerTone)
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    private func toneGroup(title: String, selected: Binding<AvatarTone>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AvatarTone.allCases, id: \.self) { tone in
                        Button {
                            Haptics.select()
                            selected.wrappedValue = tone
                        } label: {
                            Circle()
                                .fill(tone.gradient)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle().strokeBorder(
                                        selected.wrappedValue == tone ? Theme.Color.ink : .clear,
                                        lineWidth: 2.5
                                    )
                                )
                                .overlay(
                                    Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Fields

    private var fieldsBlock: some View {
        VStack(spacing: 10) {
            field(title: "Name", text: $displayName, placeholder: "Your name",
                  system: nil, limit: 40)
            VStack(alignment: .leading, spacing: 4) {
                field(title: "Handle", text: $handle, placeholder: "yourhandle",
                      system: "at", limit: 24, lowercased: true)
                handleHint
            }
            field(title: "Location", text: $location, placeholder: "Brooklyn, NY",
                  system: "mappin.circle", limit: 40)
            field(title: "Pronouns", text: $pronouns,
                  placeholder: "she/her, he/him, they/them",
                  system: "person.fill", limit: 40)
            VStack(alignment: .leading, spacing: 4) {
                field(title: "Website", text: $website,
                      placeholder: "https://your.link",
                      system: "link", limit: 120, lowercased: false,
                      autocap: .never)
                websiteHint
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Bio")
                    .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
                TextField("A line or two about you", text: $bio, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                                    .fill(Theme.Color.surface))
                HStack {
                    Spacer()
                    Text("\(bio.count) / 160")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
            }
            .padding(Theme.Space.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
        }
    }

    @ViewBuilder
    private var websiteHint: some View {
        let trimmed = website.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !websiteValid {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Needs http:// or https://")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.hot)
            .padding(.horizontal, Theme.Space.md)
        }
    }

    private struct HandleHintConfig {
        let icon: String
        let text: String
        let color: Color
    }

    private var handleHintConfig: HandleHintConfig {
        let trimmed = handle.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .init(icon: "at",
                         text: "2–24 letters, numbers, or underscores",
                         color: Theme.Color.inkFaint)
        }
        if !handleValid {
            return .init(icon: "exclamationmark.circle.fill",
                         text: trimmed.count < 2
                             ? "Needs at least 2 characters"
                             : "Only a–z, 0–9, and _",
                         color: Theme.Color.hot)
        }
        if let existing = social.me?.handle, trimmed == existing {
            return .init(icon: "checkmark.circle",
                         text: "Unchanged",
                         color: Theme.Color.inkFaint)
        }
        return .init(icon: "checkmark.circle.fill",
                     text: "Looks good",
                     color: Theme.Color.accentDeep)
    }

    private var handleHint: some View {
        let cfg = handleHintConfig
        return HStack(spacing: 4) {
            Image(systemName: cfg.icon).font(.system(size: 10, weight: .bold))
            Text(cfg.text).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(cfg.color)
        .padding(.horizontal, Theme.Space.md)
    }

    private func field(title: String,
                       text: Binding<String>,
                       placeholder: String,
                       system: String?,
                       limit: Int,
                       lowercased: Bool = false,
                       autocap: TextInputAutocapitalization = .words) -> some View {
        HStack(spacing: 10) {
            if let system {
                Image(systemName: system)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkSoft)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
                TextField(placeholder, text: text)
                    .font(.bodyL)
                    .textInputAutocapitalization(lowercased ? .never : autocap)
                    .autocorrectionDisabled(lowercased)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        var v = newValue
                        if v.count > limit { v = String(v.prefix(limit)) }
                        if lowercased { v = v.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" } }
                        if v != newValue { text.wrappedValue = v }
                    }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Color.bgElevated))
    }

    // MARK: - Showcase

    private var showcaseBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Showcase")
                    .font(.titleM).foregroundStyle(Theme.Color.ink)
                Spacer()
                Text("\(showcase.count) / 3")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Color.inkSoft)
            }
            Text("Pin up to 3 trophies that show up first on your profile.")
                .font(.bodyS).foregroundStyle(Theme.Color.inkSoft)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { idx in
                    slot(index: idx)
                }
            }
            Button {
                Haptics.tap(); showcasePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .bold))
                    Text("Pick trophies")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Theme.Color.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.Color.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Space.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    private func slot(index: Int) -> some View {
        let trophy: Trophy? = showcase.indices.contains(index)
            ? social.trophies.first(where: { $0.id == showcase[index] })
            : nil
        return Group {
            if let t = trophy {
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(colors: t.gradient.isEmpty
                                               ? [Theme.Color.accent, Theme.Color.accentDeep]
                                               : t.gradient,
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
                            )
                            .frame(height: 76)
                        Image(systemName: t.icon)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                        Button {
                            Haptics.tap()
                            showcase.removeAll { $0 == t.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.4)).padding(-2))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 34, y: -28)
                    }
                    Text(t.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                }
            } else {
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.Color.stroke,
                                          style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .frame(height: 76)
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.Color.inkFaint)
                    }
                    Text("Empty")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load/save

    private func load() {
        guard let me = social.me else { return }
        displayName = me.displayName
        handle = me.handle
        bio = me.bio ?? ""
        location = me.location ?? ""
        pronouns = me.pronouns ?? ""
        website = me.websiteUrl ?? ""
        avatarTone = me.avatarTone
        bannerTone = me.bannerTone
        showcase = me.showcasedTrophyIDs
    }

    /// When the PhotosPicker fires, we do two things:
    ///   1. Stash the raw bytes locally for preview render (photoData).
    ///   2. Downscale + re-encode as JPEG and upload via POST /v1/media/avatar.
    /// The resulting R2 key is saved on save(); if the upload fails we
    /// surface an alert and leave the local preview in place so the user
    /// can retry by picking the photo again.
    private func loadPhoto() async {
        guard let item = photoItem else { return }
        guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
        photoData = raw
        clearPhoto = false
        uploadedAvatarKey = nil
        await uploadPickedPhoto(raw)
    }

    private func uploadPickedPhoto(_ raw: Data) async {
        isUploading = true
        defer { isUploading = false }
        // Downscale to 1024 px max edge + re-encode as JPEG 0.85.
        // Strips EXIF as a side effect, and keeps every upload well
        // under the 5 MB server cap.
        let encoded = Self.jpegAtMaxEdge(raw, maxEdge: 1024, quality: 0.85) ?? raw
        do {
            let (_, key) = try await APIClient.shared.uploadAvatar(
                data: encoded, mime: "image/jpeg"
            )
            uploadedAvatarKey = key
        } catch {
            uploadError = (error as? APIError).map { err in
                switch err {
                case .notImplemented: return "Upload not available."
                case .transport(let e): return e.localizedDescription
                case .server(let code, let msg):
                    return msg.isEmpty ? "Server error (\(code))" : msg
                }
            } ?? error.localizedDescription
        }
    }

    /// CoreGraphics-based downscale → JPEG. Done inline so we don't
    /// carry a 12 MP HEIC through the upload pipeline.
    private static func jpegAtMaxEdge(
        _ data: Data, maxEdge: CGFloat, quality: CGFloat
    ) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        let ui = UIImage(cgImage: cg)
        return ui.jpegData(compressionQuality: quality)
    }

    private func save() {
        let trimmedBio = String(bio.prefix(160))
        let photoChange: Data??
        if clearPhoto { photoChange = .some(nil) }
        else if let newPhoto = photoData { photoChange = .some(newPhoto) }
        else { photoChange = nil }

        SocialDataService.shared.updateProfile(
            displayName: displayName,
            handle: handle,
            bio: trimmedBio,
            location: location,
            avatarTone: avatarTone,
            bannerTone: bannerTone,
            photoData: photoChange,
            showcasedTrophyIDs: Array(showcase.prefix(3)),
            pronouns: pronouns,
            websiteUrl: website,
            avatarR2Key: clearPhoto ? "" : uploadedAvatarKey
        )
        Haptics.success()
        dismiss()
    }
}

// MARK: - Showcase picker

struct ShowcasePickerSheet: View {
    @Binding var selected: [UUID]
    @Environment(SocialDataService.self) private var social
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Pick up to 3 trophies to pin to your profile.")
                        .font(.bodyM).foregroundStyle(Theme.Color.inkSoft)
                        .padding(.horizontal, Theme.Space.md)
                    let cols = [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)]
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(social.trophies.filter { $0.isUnlocked }) { t in
                            Button {
                                toggle(t.id)
                            } label: {
                                TrophyPickerCard(
                                    trophy: t,
                                    isSelected: selected.contains(t.id),
                                    index: selected.firstIndex(of: t.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Space.md)
                    if social.trophies.allSatisfy(\.isLocked) {
                        Text("You haven't unlocked any trophies yet. Keep moving!")
                            .font(.bodyS).foregroundStyle(Theme.Color.inkFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Space.xl)
                    }
                }
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Showcase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        Haptics.select()
        if let i = selected.firstIndex(of: id) {
            selected.remove(at: i)
        } else if selected.count < 3 {
            selected.append(id)
        } else {
            Haptics.warn()
        }
    }
}

struct TrophyPickerCard: View {
    let trophy: Trophy
    let isSelected: Bool
    let index: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(colors: trophy.gradient.isEmpty
                                       ? [Theme.Color.accent, Theme.Color.accentDeep]
                                       : trophy.gradient,
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .frame(height: 96)
                    .overlay(
                        Image(systemName: trophy.icon)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                    )
                if isSelected, let i = index {
                    Text("\(i + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.Color.accent))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .padding(8)
                }
            }
            Text(trophy.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            HStack(spacing: 4) {
                Circle().fill(trophy.rarity.tint).frame(width: 6, height: 6)
                Text(trophy.rarity.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(trophy.rarity.tint)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.Color.bgElevated))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Theme.Color.accent : .clear, lineWidth: 2)
        )
    }
}
