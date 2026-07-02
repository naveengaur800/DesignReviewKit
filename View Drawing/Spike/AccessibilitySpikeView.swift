//
//  AccessibilitySpikeView.swift
//  View Drawing
//
//  Created by Naveen Gaur on 03/07/2026.
//

import SwiftUI
import UIKit

/// Feasibility harness for AccessibilityInspector-SPEC §7.
///
/// On appear it walks the sample SwiftUI subtree with the public-API probe
/// under two conditions in one launch — as-launched, then after a lazy runtime
/// enable — and renders the counts. Launch with `-SpikeEnableAXAtLaunch 1` to
/// measure the launch-time condition (the "as-launched" run then reflects it).
///
/// Self-driving so results can be captured without interaction; the Re-run
/// button re-walks for manual sessions.
struct AccessibilitySpikeView: View {

    @State
    private var runner = SpikeRunner()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    verdictCard
                    conditionsCard
                    nodeListCard
                    sampleUnderTest
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("A11y Runtime Spike")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Re-run") {
                        Task { await runner.runLazySequence() }
                    }
                }
            }
        }
        .task { await runner.runLazySequence() }
    }

    // MARK: - Cards

    private var verdictCard: some View {
        let verdict = runner.verdict
        return VStack(alignment: .leading, spacing: 6) {
            Label(verdict.headline, systemImage: verdict.symbol)
                .font(.headline)
                .foregroundStyle(verdict.tint)
            Text(verdict.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(verdict.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var conditionsCard: some View {
        VStack(spacing: 0) {
            conditionRow(
                title: "As launched",
                subtitle: runner.appearEnabled ? "runtime ON at launch" : "runtime OFF (no enabler)",
                count: runner.countAsLaunched,
                labeled: runner.labeledAsLaunched
            )
            Divider()
            conditionRow(
                title: "After lazy enable",
                subtitle: runner.lazyEnableSucceeded ? "enableAutomation() → true" : "enable unavailable",
                count: runner.countAfterLazy,
                labeled: runner.labeledAfterLazy
            )
        }
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func conditionRow(title: String, subtitle: String, count: Int, labeled: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(count < 0 ? "—" : "\(count)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(count > 0 ? Color.green : Color.secondary)
                Text("elements · \(max(labeled, 0)) labeled")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sampleUnderTest: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAMPLE UNDER TEST (isolated hosting controller)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ProbedSampleHost { view in runner.hostView = view }
                .frame(height: 320)
        }
    }

    private var nodeListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECOVERED ELEMENTS (richest run)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if runner.nodes.isEmpty {
                Text("No elements recovered.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(runner.nodes) { node in
                    nodeRow(node)
                    if node.id != runner.nodes.last?.id { Divider() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func nodeRow(_ node: ProbedNode) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: node.hasLabel ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(node.hasLabel ? Color.green : Color.orange)
                    .font(.caption)
                Text(node.hasLabel ? (node.label ?? "") : "— no label —")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(node.hasLabel ? Color.primary : Color.orange)
            }
            let traits = node.traitNames.isEmpty ? "no traits" : node.traitNames.joined(separator: ", ")
            Text("\(traits) · \(node.sourceClass)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            if let value = node.value, !value.isEmpty {
                Text("value: \(value)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

/// Drives the walk sequence and holds the results for the harness.
@MainActor
@Observable
final class SpikeRunner {

    var hostView: UIView?

    private(set) var appearEnabled = false
    private(set) var lazyEnableSucceeded = false
    private(set) var countAsLaunched = -1
    private(set) var labeledAsLaunched = -1
    private(set) var countAfterLazy = -1
    private(set) var labeledAfterLazy = -1
    private(set) var nodes: [ProbedNode] = []

    private let probe = AccessibilityProbe()

    struct Verdict {
        let headline: String
        let detail: String
        let symbol: String
        let tint: Color
    }

    var verdict: Verdict {
        guard countAsLaunched >= 0 || countAfterLazy >= 0 else {
            return Verdict(headline: "Running…", detail: "Walking the sample subtree.", symbol: "hourglass", tint: .secondary)
        }
        if appearEnabled, countAsLaunched > 0 {
            return Verdict(
                headline: "Launch-time enable works",
                detail: "Runtime was ON at launch; the public-API walk recovered \(countAsLaunched) elements from the SwiftUI subtree.",
                symbol: "checkmark.seal.fill",
                tint: .green
            )
        }
        if countAsLaunched <= 0, countAfterLazy > 0 {
            return Verdict(
                headline: "Lazy enable works",
                detail: "With the runtime off the walk found \(max(countAsLaunched, 0)); after enableAutomation() it recovered \(countAfterLazy). The host enabler is sufficient.",
                symbol: "checkmark.seal.fill",
                tint: .green
            )
        }
        if countAsLaunched <= 0, countAfterLazy <= 0 {
            return Verdict(
                headline: "SwiftUI tree empty",
                detail: "Neither condition recovered elements — the enabler did not materialize SwiftUI nodes here. Launch-time enable or a manual toggle is required.",
                symbol: "xmark.octagon.fill",
                tint: .red
            )
        }
        return Verdict(
            headline: "Elements recovered",
            detail: "As-launched \(max(countAsLaunched, 0)), after lazy enable \(max(countAfterLazy, 0)).",
            symbol: "info.circle.fill",
            tint: .blue
        )
    }

    /// Walk as-launched, enable the runtime, then walk again after a settle.
    func runLazySequence() async {
        guard let hostView = await waitForHostView() else { return }

        appearEnabled = AXRuntimeEnabler.isAutomationEnabled

        let asLaunched = probe.walk(hostView)
        countAsLaunched = asLaunched.count
        labeledAsLaunched = asLaunched.filter(\.hasLabel).count

        lazyEnableSucceeded = AXRuntimeEnabler.enableAutomation()
        hostView.setNeedsLayout()
        hostView.layoutIfNeeded()
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
        try? await Task.sleep(for: .milliseconds(600))

        let afterLazy = probe.walk(hostView)
        countAfterLazy = afterLazy.count
        labeledAfterLazy = afterLazy.filter(\.hasLabel).count

        nodes = afterLazy.count >= asLaunched.count ? afterLazy : asLaunched
        dump(asLaunched: asLaunched, afterLazy: afterLazy)
    }

    /// Emit an authoritative text dump so the exact per-node readings can be
    /// read from the launch console (no scrolling / OCR).
    private func dump(asLaunched: [ProbedNode], afterLazy: [ProbedNode]) {
        print("SPIKE|automationAtAppear=\(appearEnabled) lazyEnableSucceeded=\(lazyEnableSucceeded)")
        print("SPIKE|asLaunched=\(asLaunched.count) labeled=\(labeledAsLaunched) | afterLazy=\(afterLazy.count) labeled=\(labeledAfterLazy)")
        for (index, node) in nodes.enumerated() {
            let traits = node.traitNames.isEmpty ? "—" : node.traitNames.joined(separator: "+")
            print("SPIKE|[\(index)] label=\(node.label.map { "\"\($0)\"" } ?? "nil") value=\(node.value ?? "nil") hint=\(node.hint ?? "nil") id=\(node.identifier ?? "nil") traits=\(traits) class=\(node.sourceClass)")
        }
    }

    /// Poll briefly for the embedded hosting view to appear and lay out.
    private func waitForHostView() async -> UIView? {
        for _ in 0..<20 {
            if let hostView, hostView.bounds.width > 0 { return hostView }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return hostView
    }
}
