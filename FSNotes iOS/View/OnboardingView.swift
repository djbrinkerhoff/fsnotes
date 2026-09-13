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
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if selection < pages.count - 1 {
                    withAnimation(.snappy) { selection += 1 }
                } else {
                    onDone()
                }
            } label: {
                Text(selection < pages.count - 1
                     ? NSLocalizedString("Continue", comment: "Onboarding")
                     : NSLocalizedString("Start Writing", comment: "Onboarding"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button(NSLocalizedString("Skip", comment: "Onboarding")) {
                onDone()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
            .opacity(selection < pages.count - 1 ? 1 : 0)
        }
        .background(SwiftUI.Color(uiColor: .systemBackground))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct OnboardingPageView: View {
    var page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(LinearGradient(colors: page.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 220, height: 220)
                    .shadow(color: page.gradient.last?.opacity(0.35) ?? .clear, radius: 24, y: 12)

                SwiftUI.Image(systemName: page.systemImage)
                    .font(.system(size: 88, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
