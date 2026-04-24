import SwiftUI
import PhotosUI

struct EditProfileSheet: View {
    @Environment(SocialDataService.self) private var social
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var handle: String = ""
    @State private var bio: String = ""
    @State private var location: String = ""
    @State private var avatarTone: AvatarTone = .sunset
    @State private var bannerTone: AvatarTone = .sunset
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var clearPhoto: Bool = false
    @State private var showcase: [UUID] = []
    @State private var showcasePicker = false

    /// Matches the server's Zod constraint (`/^[a-z0-9_]{2,24}$/`).
    /// Rendered inline under the handle field, and gates Save.
    private var handleValid: Bool {
        let trimmed = handle.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.count <= 24 else { return false }
        return trimmed.allSatisfy { $0.isLetter && $0.isLowercase || $0.isNumber || $0 == "_" }
    }

    /// Name is required (any non-whitespace); handle must be valid.
    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && handleValid
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
            .onAppear(perform: load)
            .onChange(of: photoItem) {
                Task { await loadPhoto() }
            }
        }
    }

    // MARK: - Avatar

    private var avatarBlock: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(bannerTone.gradient)
                    .frame(width: 160, height: 160)
                    .opacity(0.35)
                    .blur(radius: 30)
                previewAvatar
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 3))
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
            }

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
                       lowercased: Bool = false) -> some View {
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
                    .textInputAutocapitalization(lowercased ? .never : .words)
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
        avatarTone = me.avatarTone
        bannerTone = me.bannerTone
        showcase = me.showcasedTrophyIDs
    }

    private func loadPhoto() async {
        guard let item = photoItem else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            photoData = data
            clearPhoto = false
        }
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
            showcasedTrophyIDs: Array(showcase.prefix(3))
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
                        ForEach(social.trophies.filter { !$0.isLocked }) { t in
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
