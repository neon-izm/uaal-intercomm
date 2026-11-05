import SwiftUI
import UaalIntercomm

struct ContentView: View {
    var body: some View {
        NavigationView {
            HomeView()
        }
        .navigationViewStyle(.stack)
    }
}

private struct HomeView: View {
    @State private var status = "起動しています"
    @State private var ready = false

    var body: some View {
        VStack(spacing: 24) {
            Text(status)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            NavigationLink("車を見る") {
                CarView()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!ready)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("uaal-intercomm")
        .task {
            await boot()
        }
    }

    private func boot() async {
        do {
            status = "起動しています"
            try await UnityHost.shared.initialize()
            try await UnityHost.shared.load()
            UnityHost.shared.keepOffscreen()
            ready = true
            status = "準備できました"
        } catch {
            status = message(error)
        }
    }
}

private struct CarView: View {
    @State private var status = "車を選んでください"
    @State private var busy = false
    @State private var loaded = true

    private let cars: [(PrefabId, String)] = [
        (.carA, "セダン"),
        (.carB, "SUV"),
        (.carC, "レース"),
    ]
    private let colors: [(String, Float, Float, Float)] = [
        ("白", 1, 1, 1),
        ("赤", 0.8, 0.1, 0.1),
        ("青", 0.15, 0.35, 0.9),
        ("黒", 0.08, 0.08, 0.08),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                UnityView()
                    .frame(height: 520)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)

                carRow
                colorRow
                cameraRow
            }
            .padding(16)
        }
        .navigationTitle("車")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            UnityHost.shared.keepOffscreen()
        }
    }

    private var carRow: some View {
        HStack {
            ForEach(cars, id: \.0) { car in
                Button(car.1) {
                    Task { await show(car.0) }
                }
                .disabled(!loaded || busy)
            }
        }
    }

    private var colorRow: some View {
        HStack {
            ForEach(colors, id: \.0) { color in
                Button(color.0) {
                    paint(r: color.1, g: color.2, b: color.3)
                }
                .disabled(!loaded || busy)
            }
        }
    }

    private var cameraRow: some View {
        HStack {
            ForEach(1...3, id: \.self) { index in
                Button(cameraTitle(index)) {
                    look(from: index)
                }
                .disabled(!loaded || busy)
            }
        }
    }

    private func show(_ id: PrefabId) async {
        await run("\(title(id))を読み込んでいます") {
            try await UnityHost.shared.loadPrefab(id)
            status = "\(title(id))を表示しました"
        }
    }

    private func paint(r: Float, g: Float, b: Float) {
        do {
            try UnityHost.shared.setColor(r: r, g: g, b: b)
            status = "色を変えました"
        } catch {
            status = message(error)
        }
    }

    private func look(from index: Int) {
        do {
            try UnityHost.shared.setCamera(index)
            status = "\(cameraTitle(index))に切り替えました"
        } catch {
            status = message(error)
        }
    }

    private func run(_ progress: String, _ body: () async throws -> Void) async {
        busy = true
        status = progress
        do {
            try await body()
        } catch {
            status = message(error)
        }
        busy = false
    }

    private func title(_ id: PrefabId) -> String {
        switch id {
        case .carA:
            return "セダン"
        case .carB:
            return "SUV"
        case .carC:
            return "レース"
        }
    }

    private func cameraTitle(_ index: Int) -> String {
        switch index {
        case 1:
            return "正面"
        case 2:
            return "側面"
        case 3:
            return "上面"
        default:
            return "カメラ\(index)"
        }
    }
}

private func message(_ error: Error) -> String {
    if let error = error as? UnityHostError {
        return error.description
    }
    return error.localizedDescription
}
