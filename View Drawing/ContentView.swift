//
//  ContentView.swift
//  View Drawing
//
//  Created by Naveen Gaur on 10/6/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            DemoCardScreen()
        }
        .onShakePresentInspector()
    }
}

/// Demo screen for exercising the inspector: a profile card with icon, text, and buttons.
private struct DemoCardScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileCard
                statsCard

                NavigationLink {
                    DemoSettingsScreen()
                } label: {
                    HStack {
                        Label("Appearance Settings", systemImage: "paintbrush")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Showcase")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InspectorToolbarButton()
            }
        }
    }

    private var profileCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 4) {
                Text("Ava Martinez")
                    .font(.title2.bold())
                Text("Senior Product Designer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Crafting delightful interfaces and obsessing over 2pt misalignments since 2018.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            // Custom (non-system) face so typography mode demos font extraction
            // beyond SF Pro.
            Text("ava.design")
                .font(.custom("Avenir-Heavy", size: 13))
                .foregroundStyle(.tint)

            HStack(spacing: 12) {
                Button {
                } label: {
                    Text("Follow")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("profile_follow_button")
                .accessibilityHint("Follows Ava and adds her to your feed")

                Button {
                } label: {
                    Text("Message")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statsCard: some View {
        HStack {
            stat(value: "128", label: "Shots")
            Divider().frame(height: 32)
            stat(value: "4.2k", label: "Followers")
            Divider().frame(height: 32)
            stat(value: "312", label: "Following")
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Second demo screen so multi-screen sessions can be exercised.
private struct DemoSettingsScreen: View {

    @State
    private var useDynamicType = true

    @State
    private var reduceMotion = false

    @State
    private var cornerRadius = 12.0

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Dynamic Type", isOn: $useDynamicType)
                Toggle("Reduce Motion", isOn: $reduceMotion)
            }

            Section("Card Style") {
                VStack(alignment: .leading) {
                    Text("Corner Radius: \(Int(cornerRadius))")
                        .font(.subheadline)
                    Slider(value: $cornerRadius, in: 0...24, step: 1)
                }
            }
        }
        .navigationTitle("Appearance")
    }
}

#Preview {
    ContentView()
}
