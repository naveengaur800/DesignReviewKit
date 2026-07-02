//
//  SpikeSampleContent.swift
//  View Drawing
//
//  Created by Naveen Gaur on 03/07/2026.
//

import SwiftUI
import UIKit

/// Representative SwiftUI content walked by the probe: a spread of accessibility
/// shapes the real inspector must handle — derived labels, explicit labels, a
/// deliberately unlabeled image, a switch, and a synthesized adjustable element.
struct SpikeSampleContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ava Martinez")
                .font(.headline)

            Button("Follow") {}
                .buttonStyle(.borderedProminent)

            Button {
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .accessibilityLabel("Send message")

            Image(systemName: "checkmark.seal.fill")
                .accessibilityLabel("Verified")

            // Deliberately unlabeled — the probe should still see an element,
            // and the real inspector will flag it as .unlabeledImage.
            Image(systemName: "bell.fill")

            Toggle("Notifications", isOn: .constant(true))
                .labelsHidden()
                .accessibilityLabel("Notifications")

            Text("Rating")
                .accessibilityElement()
                .accessibilityLabel("Rating")
                .accessibilityValue("4 stars")
                .accessibilityHint("Swipe up or down to adjust")
                .accessibilityAdjustableAction { _ in }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Host the sample content in its own `UIHostingController` and hand the hosting
/// view back, so the probe walks exactly that SwiftUI subtree in isolation.
struct ProbedSampleHost: UIViewControllerRepresentable {

    let onHostView: (UIView) -> Void

    func makeUIViewController(context: Context) -> UIHostingController<SpikeSampleContent> {
        let controller = UIHostingController(rootView: SpikeSampleContent())
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<SpikeSampleContent>, context: Context) {
        onHostView(controller.view)
    }
}
