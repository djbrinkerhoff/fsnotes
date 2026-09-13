//
//  OnboardingView.swift
//  FSNotes iOS
//
//  Craft-style welcome carousel shown on first launch.
//

import SwiftUI

struct OnboardingPage: Identifiable {
    var id: Int
    var title: String
    var message: String
    var systemImage: String
    var gradient: [SwiftUI.Color]
}

struct OnboardingView: View {
    var onDone: () -> Void

    @State private var selection = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: NSLocalizedString("Capture Thoughts Instantly", comment: "Onboarding"),
            message: NSLocalizedString("Every note is a plain Markdown file in your own folders. Start from Home, the daily note, or the new note button, and pick up on any device through iCloud Drive.", comment: "Onboarding"),
            systemImage: "square.and.pencil",
            gradient: [SwiftUI.Color(red: 0.36, green: 0.55, blue: 1.0), SwiftUI.Color(red: 0.62, green: 0.40, blue: 0.98)]
        ),
        OnboardingPage(
            id: 1,
            title: NSLocalizedString("Colors, Your Way", comment: "Onboarding"),
            message: NSLocalizedString("Give folders a color and an icon so your library is easy to scan. Choose how each folder is displayed: list, compact or cards.", comment: "Onboarding"),
            systemImage: "paintpalette.fill",
            gradient: [SwiftUI.Color(red: 1.0, green: 0.58, blue: 0.30), SwiftUI.Color(red: 0.99, green: 0.30, blue: 0.45)]
        ),
        OnboardingPage(
            id: 2,
            title: NSLocalizedString("Easier Tagging", comment: "Onboarding"),
            message: NSLocalizedString("Type #tags right inside your writing. Nested tags like #work/ideas stay organized and show up on Home.", comment: "Onboarding"),
            systemImage: "number",
            gradient: [SwiftUI.Color(red: 0.20, green: 0.78, blue: 0.62), SwiftUI.Color(red: 0.16, green: 0.55, blue: 0.85)]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(pages) { page in
                    OnboardingPageView(page: page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay(alignment: .topTrailing) {
                Button(NSLocalizedString("Close", comment: ""), systemImage: "xmark") {
                    onDone()
                }
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.thinMaterial, in: Circle())
                .padding(16)
            }

            HStack(spacing: 8) {
                ForEach(pages) { page in
                    Circle()
                        .fill(page.id == selection ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.vertical, 18)
            .accessibilityHidden(true)

            Button {
                if selection < pages.count - 1 {
                    withAnimation(.snappy) { selection += 1 }
                } else {
                    onDone()
                }
            } label: {
                Text(selection < pages.count - 1
                     ? NSLocalizedString("Next", comment: "Onboarding")
                     : NSLocalizedString("Start Writing", comment: "Onboarding"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(SwiftUI.Color(uiColor: .systemGroupedBackground))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct OnboardingPageView: View {
    var page: OnboardingPage

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: page.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.35), .clear], center: .bottomLeading, startRadius: 20, endRadius: 320)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.92))
                    .frame(width: 180, height: 180)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                    .overlay(
                        SwiftUI.Image(systemName: page.systemImage)
                            .font(.system(size: 72, weight: .medium))
                            .foregroundStyle(LinearGradient(colors: page.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
