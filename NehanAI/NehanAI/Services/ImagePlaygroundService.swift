import SwiftUI
import ImagePlayground

@available(iOS 18.0, *)
struct ExpressionPlaygroundView: View {
    let sleepQuality: String
    let stepCount: Int
    let mood: String?

    @State private var generatedImage: Image?
    @State private var isPresented = false

    var body: some View {
        Group {
            if let img = generatedImage {
                img
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "face.smiling")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture { isPresented = true }
            }
        }
        .imagePlaygroundSheet(
            isPresented: $isPresented,
            concepts: buildConcepts()
        ) { url in
            if let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                generatedImage = Image(uiImage: uiImage)
            }
        }
    }

    private func buildConcepts() -> [ImagePlaygroundConcept] {
        var concepts: [ImagePlaygroundConcept] = []
        concepts.append(.text("A cute character expressing today's mood"))
        if !sleepQuality.isEmpty {
            concepts.append(.text("Sleep quality: \(sleepQuality)"))
        }
        if stepCount > 6000 {
            concepts.append(.text("Active and energetic"))
        }
        if let mood, !mood.isEmpty {
            concepts.append(.text(mood))
        }
        return concepts
    }
}
