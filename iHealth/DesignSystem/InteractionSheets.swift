import SwiftUI
import UIKit

// MARK: - System share sheet wrapper
// SwiftUI's `ShareLink` works for a plain button label, but our custom styled
// pills/chromes can't be retrofitted without losing their visual treatment.
// This wrapper lets any `.sheet(isPresented:)` caller present the native
// UIActivityViewController with arbitrary items.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiVC: UIActivityViewController, context: Context) {}
}

// MARK: - Coming-soon sheet
// Used for features the UI suggests but that we haven't shipped yet
// (Messaging, Tipping, Cash-out). We don't want to ghost the tap — a
// transparent "on the roadmap" sheet reads better than a dead button.
struct ComingSoonSheet: View {
    let icon: String
    let title: String
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Theme.Color.accent.opacity(0.18))
                    .frame(width: 96, height: 96)
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.Color.accentDeep)
            }
            VStack(spacing: 8) {
                Text(title)
                    .font(.displayS)
                    .foregroundStyle(Theme.Color.ink)
                Text(message)
                    .font(.bodyM)
                    .foregroundStyle(Theme.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.lg)
            }
            Text("Coming soon")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Theme.Color.accentDeep)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.Color.accent.opacity(0.18)))
            Spacer()
            PrimaryButton(title: "Got it") { dismiss() }
        }
        .padding(Theme.Space.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.xl)
    }
}

// MARK: - Add shoe sheet

struct AddShoeSheet: View {
    @Environment(SocialDataService.self) private var social
    @Environment(\.dismiss) private var dismiss

    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var nickname: String = ""
    @State private var tone: AvatarTone = .sunset
    @State private var milesTotal: Double = 800
    @FocusState private var focus: Field?

    enum Field { case brand, model, nickname }

    private var canSave: Bool {
        !brand.trimmingCharacters(in: .whitespaces).isEmpty
        && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    preview
                    VStack(alignment: .leading, spacing: 10) {
                        field("Brand", text: $brand, focus: .brand, placeholder: "Nike, Hoka, Saucony…")
                        field("Model", text: $model, focus: .model, placeholder: "Vaporfly 3")
                        field("Nickname (optional)", text: $nickname, focus: .nickname, placeholder: "Long run shoes")
                    }
                    tonePicker
                    mileageSlider
                    Color.clear.frame(height: 40)
                }
                .padding(Theme.Space.lg)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("Add gear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        social.addShoe(brand: brand, model: model,
                                       nickname: nickname.isEmpty ? nil : nickname,
                                       tone: tone, milesTotal: milesTotal)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var preview: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(tone.gradient)
                    .frame(width: 72, height: 72)
                Image(systemName: "shoe.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(brand.isEmpty ? "Brand" : brand)
                    .font(.titleM)
                    .foregroundStyle(brand.isEmpty ? Theme.Color.inkFaint : Theme.Color.ink)
                Text(model.isEmpty ? "Model" : model)
                    .font(.bodyM)
                    .foregroundStyle(model.isEmpty ? Theme.Color.inkFaint : Theme.Color.inkSoft)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgElevated))
    }

    private func field(_ label: String, text: Binding<String>, focus f: Field, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
            TextField(placeholder, text: text)
                .focused($focus, equals: f)
                .font(.bodyL)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(focus == f ? Theme.Color.accent : Theme.Color.stroke, lineWidth: 1)
                )
        }
    }

    private var tonePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AvatarTone.allCases, id: \.self) { t in
                        Button {
                            Haptics.select(); tone = t
                        } label: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(t.gradient)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(tone == t ? Theme.Color.ink : .clear, lineWidth: 2.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var mileageSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Expected life")
                    .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
                Spacer()
                Text("\(Int(milesTotal)) km")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
            }
            Slider(value: $milesTotal, in: 200...1500, step: 50)
                .tint(Theme.Color.accent)
            Text("Most running shoes tire out around 500–800 km. We'll nudge you when yours does.")
                .font(.footnote).foregroundStyle(Theme.Color.inkFaint)
        }
    }
}

// MARK: - Create club sheet

struct CreateClubSheet: View {
    @Environment(SocialDataService.self) private var social
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var handle: String = ""
    @State private var tagline: String = ""
    @State private var description: String = ""
    @State private var tone: AvatarTone = .ocean
    @FocusState private var focus: Field?

    enum Field { case name, handle, tagline, description }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !handle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    heroPreview
                    VStack(alignment: .leading, spacing: 10) {
                        field("Name", text: $name, focus: .name, placeholder: "Dawn Patrol Runners")
                        field("Handle", text: $handle, focus: .handle, placeholder: "dawn_patrol")
                            .onChange(of: handle) { _, new in
                                handle = String(new.lowercased().prefix(24)
                                                 .filter { $0.isLetter || $0.isNumber || $0 == "_" })
                            }
                        field("Tagline", text: $tagline, focus: .tagline, placeholder: "Early birds, long miles.")
                    }
                    tonePicker
                    descField
                    Color.clear.frame(height: 40)
                }
                .padding(Theme.Space.lg)
            }
            .background(Theme.Color.bg.ignoresSafeArea())
            .navigationTitle("New club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        social.createClub(name: name, handle: handle,
                                          tagline: tagline, description: description,
                                          tone: tone)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var heroPreview: some View {
        ZStack(alignment: .bottomLeading) {
            tone.gradient
                .frame(height: 120)
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Club name" : name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("@\(handle.isEmpty ? "handle" : handle)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private func field(_ label: String, text: Binding<String>, focus f: Field, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
            TextField(placeholder, text: text)
                .focused($focus, equals: f)
                .font(.bodyL)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(focus == f ? Theme.Color.accent : Theme.Color.stroke, lineWidth: 1)
                )
        }
    }

    private var tonePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Banner")
                .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AvatarTone.allCases, id: \.self) { t in
                        Button {
                            Haptics.select(); tone = t
                        } label: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(t.gradient)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(tone == t ? Theme.Color.ink : .clear, lineWidth: 2.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var descField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About")
                .font(.labelBold).foregroundStyle(Theme.Color.inkSoft)
            TextEditor(text: $description)
                .focused($focus, equals: .description)
                .font(.bodyL)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(focus == .description ? Theme.Color.accent : Theme.Color.stroke, lineWidth: 1)
                )
        }
    }
}

// MARK: - Feed sort sheet

struct FeedSortSheet: View {
    @Binding var sort: FeedSort
    @Environment(\.dismiss) private var dismiss

    enum FeedSort: String, CaseIterable, Identifiable {
        case recent, mostKudos, closestFriends
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recent: return "Most recent"
            case .mostKudos: return "Most kudos"
            case .closestFriends: return "Closest friends"
            }
        }
        var icon: String {
            switch self {
            case .recent: return "clock.fill"
            case .mostKudos: return "bolt.heart.fill"
            case .closestFriends: return "person.2.fill"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Sort feed")
                .font(.displayS).foregroundStyle(Theme.Color.ink)
                .padding(.top, Theme.Space.md)
            VStack(spacing: 0) {
                ForEach(Array(FeedSort.allCases.enumerated()), id: \.element.id) { idx, s in
                    Button {
                        Haptics.select()
                        sort = s
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: s.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.Color.accentDeep)
                                .frame(width: 24)
                            Text(s.title)
                                .font(.bodyL).foregroundStyle(Theme.Color.ink)
                            Spacer()
                            if sort == s {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.Color.accentDeep)
                            }
                        }
                        .padding(.horizontal, Theme.Space.md).padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    if idx < FeedSort.allCases.count - 1 { Divider().padding(.leading, 52) }
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgElevated))
            Spacer()
        }
        .padding(Theme.Space.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.xl)
    }
}
