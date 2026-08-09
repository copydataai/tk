import Foundation

enum SpeechProfileKind: String, CaseIterable, Sendable {
    case dictation
    case reading
}

struct SpeechProfile: Identifiable, Hashable, Sendable {
    let id: String
    let kind: SpeechProfileKind
    let name: String
    let bestFor: String
    let downloadSize: String
    let memory: String
    let byteCount: Int64
    let filename: String
    let sha256: String
    let sourceRevision: String
    let downloadURL: URL
    let isBundled: Bool

    var notice: String? {
        switch id {
        case "dictation.best-quality": "Uses substantially more memory."
        case "reading.lower-memory": "May begin reading more slowly."
        default: nil
        }
    }

    var supportedTarget: String { "macOS 14 or newer · Apple silicon" }
    var runtimeIdentity: String {
        kind == .dictation
            ? "whisper.cpp v1.9.1 · Metal"
            : "Babylon 208e3d3d0d8305bb7c9ffa7d16a0c889cd0d2cae · CPU ONNX Runtime"
    }
    var licenseSummary: String {
        kind == .dictation
            ? "OpenAI Whisper / whisper.cpp MIT; upstream MIT and Apache metadata retained"
            : "Kokoro/ONNX Apache-2.0; Babylon MIT"
    }

    static let all: [SpeechProfile] = [
        SpeechProfile(
            id: "dictation.fast",
            kind: .dictation,
            name: "Fast",
            bestFor: "Quick notes when speed and lower resource use matter more than catching every word.",
            downloadSize: "181.3 MiB",
            memory: "Low",
            byteCount: 190_085_487,
            filename: "ggml-small-q5_1.bin",
            sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb",
            sourceRevision: "whisper.cpp 5359861c739e955e79d9a303bcbc70fb988958b1",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small-q5_1.bin")!,
            isBundled: false
        ),
        SpeechProfile(
            id: "dictation.balanced",
            kind: .dictation,
            name: "Balanced",
            bestFor: "Everyday dictation with a strong balance of speed and accuracy.",
            downloadSize: "547.4 MiB",
            memory: "Moderate",
            byteCount: 574_041_195,
            filename: "ggml-large-v3-turbo-q5_0.bin",
            sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
            sourceRevision: "whisper.cpp 5359861c739e955e79d9a303bcbc70fb988958b1",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin")!,
            isBundled: true
        ),
        SpeechProfile(
            id: "dictation.best-quality",
            kind: .dictation,
            name: "Best quality",
            bestFor: "Dictation where the best accuracy offered by tk matters more than waiting and resource use.",
            downloadSize: "1.007 GiB",
            memory: "High",
            byteCount: 1_081_140_203,
            filename: "ggml-large-v3-q5_0.bin",
            sha256: "d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1",
            sourceRevision: "whisper.cpp 5359861c739e955e79d9a303bcbc70fb988958b1",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-q5_0.bin")!,
            isBundled: false
        ),
        SpeechProfile(
            id: "reading.lower-memory",
            kind: .reading,
            name: "Lower memory",
            bestFor: "Macs where storage and memory matter more than how quickly reading begins.",
            downloadSize: "88.1 MiB",
            memory: "Lower",
            byteCount: 92_361_116,
            filename: "kokoro-v1.0-quantized.onnx",
            sha256: "fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478",
            sourceRevision: "Kokoro 1939ad2a8e416c0acfeecc08a694d14ef25f2231",
            downloadURL: URL(string: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx/model_quantized.onnx")!,
            isBundled: false
        ),
        SpeechProfile(
            id: "reading.best-quality",
            kind: .reading,
            name: "Best quality",
            bestFor: "Natural everyday reading.",
            downloadSize: "310.5 MiB",
            memory: "Moderate",
            byteCount: 325_532_232,
            filename: "kokoro-v1.0-fp32.onnx",
            sha256: "8fbea51ea711f2af382e88c833d9e288c6dc82ce5e98421ea61c058ce21a34cb",
            sourceRevision: "Kokoro 1939ad2a8e416c0acfeecc08a694d14ef25f2231",
            downloadURL: URL(string: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx/model.onnx")!,
            isBundled: true
        ),
    ]

    static let defaultIDs: [SpeechProfileKind: String] = [
        .dictation: "dictation.balanced",
        .reading: "reading.best-quality",
    ]

    static func profiles(for kind: SpeechProfileKind) -> [SpeechProfile] {
        all.filter { $0.kind == kind }
    }
}

struct SpeechArtifact: Sendable {
    let profileID: String
    let url: URL
}
