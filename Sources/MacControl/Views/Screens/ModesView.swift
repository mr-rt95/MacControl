//  ModesView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Switch between normal, quiet and performance mode.
struct ModesView: View {

    @ObservedObject var model: ModesViewModel
    @ObservedObject var processes: ProcessesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            modeCard(.normal, "Normal", "Nothing is changed. Every app runs with its usual priority.", "checkmark.circle")
            modeCard(.quiet, "Quiet", "Background apps run at low priority, which lowers heat and fan noise. The app you are working in is not touched.", "moon")
            modeCard(.performance, "Performance", "Priorities return to normal and MacControl shows heavy background apps you could close to free resources.", "bolt")

            if model.mode == .quiet {
                Label(tr("%@ background processes are running at low priority.", "\(model.loweredCount)"), systemImage: "arrow.down.circle")
                    .foregroundColor(.secondary)
            }
            if model.mode == .performance { suggestionList }

            Text("Modes only change process priority. Nothing is closed unless you choose it, and MacControl cannot control CPU speed or fan speed. Quiet mode ends when you switch back or quit the app.")
                .font(.caption).foregroundColor(.secondary)
        }
        .banner($processes.banner)
        .confirmation($processes.preview)
    }

    private func modeCard(_ mode: PerformanceMode, _ title: LocalizedStringKey, _ text: LocalizedStringKey, _ symbol: String) -> some View {
        let isActive = model.mode == mode
        return Button { model.setMode(mode) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title2).frame(width: 32)
                    .foregroundColor(isActive ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(text).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isActive { Image(systemName: "checkmark").foregroundColor(.accentColor) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isActive ? Color.accentColor : .clear, lineWidth: 2)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps you could close").font(.headline)
            if model.suggestions.isEmpty {
                Text("No heavy background apps right now.").foregroundColor(.secondary)
            }
            ForEach(model.suggestions) { group in
                HStack {
                    Text(verbatim: group.name)
                    Spacer()
                    Text(verbatim: "\(Formatters.cpuPercent(group.cpuPercent)) · \(Formatters.bytes(group.memoryBytes))")
                        .monospacedDigit().foregroundColor(.secondary)
                    Button("Quit app") { processes.requestQuit(group) }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.cardBackground))
            }
        }
    }
}
