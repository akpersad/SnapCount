import Foundation
import SnapCountCore

// Enrolls one person from ReferencePhotos/ and tunes their match threshold.
//
//   swift run --package-path snapcount/SnapCountCore snapcount-enroll [options]
//
// Reads <photos>/daughter/ (the person to recognize) and <photos>/negatives/ (photos that do
// NOT contain them, ideally other children). Writes enrollment.json with the tuned threshold.
// Runs entirely offline. Nothing here touches the network.

let snapcountDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // snapcount-enroll
    .deletingLastPathComponent()  // Sources
    .deletingLastPathComponent()  // SnapCountCore
    .deletingLastPathComponent()  // snapcount

struct Options {
    var photos = snapcountDirectory.appendingPathComponent("ReferencePhotos")
    var model = snapcountDirectory.appendingPathComponent("Models/AdaFace_IR18.mlpackage")
    var output = snapcountDirectory.appendingPathComponent("Enrollment/enrollment.json")
    var id = "daughter"
    var displayName = "Daughter"
    var minimumPrecision = 0.98

    static let usage = """
        Usage: snapcount-enroll [--photos DIR] [--model PATH] [--out PATH]
                                [--id ID] [--name NAME] [--min-precision P]

          --photos         Directory holding daughter/ and negatives/ (default: ReferencePhotos)
          --model          AdaFace .mlpackage or .mlmodelc (default: Models/AdaFace_IR18.mlpackage)
          --out            Where to write enrollment.json (default: Enrollment/enrollment.json)
          --id, --name     Identifier and display name for the enrolled person
          --min-precision  Precision floor for the threshold (default: 0.98)
        """

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()
        func value(for flag: String) -> String {
            guard let v = iterator.next() else { fail("\(flag) needs a value\n\n\(usage)") }
            return v
        }
        while let argument = iterator.next() {
            switch argument {
            case "--photos": options.photos = URL(fileURLWithPath: value(for: argument))
            case "--model": options.model = URL(fileURLWithPath: value(for: argument))
            case "--out": options.output = URL(fileURLWithPath: value(for: argument))
            case "--id": options.id = value(for: argument)
            case "--name": options.displayName = value(for: argument)
            case "--min-precision":
                guard let p = Double(value(for: argument)), p > 0, p <= 1 else {
                    fail("--min-precision must be in (0, 1]")
                }
                options.minimumPrecision = p
            case "-h", "--help": print(usage); exit(0)
            default: fail("Unknown argument \(argument)\n\n\(usage)")
            }
        }
        return options
    }
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

func format(_ value: Float) -> String { String(format: "%.3f", value) }

struct Scored {
    let file: String
    let score: Float
}

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))
let targetDirectory = options.photos.appendingPathComponent("daughter")
let negativesDirectory = options.photos.appendingPathComponent("negatives")

guard FileManager.default.fileExists(atPath: options.model.path) else {
    fail("Model not found at \(options.model.path). Run Scripts/fetch-model.sh first.")
}

let embedder = try await AdaFaceIR18.embedder(contentsOf: options.model)
let detector = FaceDetector()
let enroller = Enroller(detector: detector, embedder: embedder)

// MARK: Reference photos

let targetFiles = try ImageLoading.imageFiles(in: targetDirectory)
guard !targetFiles.isEmpty else { fail("No images in \(targetDirectory.path)") }

print("Reference photos (\(targetFiles.count)):")
var references: [(file: String, embedding: FaceEmbedding)] = []
for url in targetFiles {
    let name = url.lastPathComponent
    guard let image = ImageLoading.image(at: url) else {
        print("  skip  \(name): could not decode")
        continue
    }
    if let embedding = try await enroller.largestFaceEmbedding(in: image) {
        references.append((name, embedding))
        print("  ok    \(name)")
    } else {
        print("  skip  \(name): no face passed the quality, size, and pose filters")
    }
}

if references.count < 10 {
    print("\nwarning: only \(references.count) usable reference faces. Aim for at least 10, "
        + "across varied angles, lighting, and ages from the last year.")
}

// MARK: Negatives

// Every face in a negative photo counts, not just the largest, because in real use any
// stranger in frame is a chance for a false positive.
var negatives: [(file: String, embedding: FaceEmbedding)] = []
let negativeFiles = (try? ImageLoading.imageFiles(in: negativesDirectory)) ?? []
for url in negativeFiles {
    guard let image = ImageLoading.image(at: url) else { continue }
    for embedding in try await enroller.allFaceEmbeddings(in: image) {
        negatives.append((url.lastPathComponent, embedding))
    }
}

guard let evaluation = EnrollmentEvaluator.evaluate(
    id: options.id,
    displayName: options.displayName,
    references: references.map(\.embedding),
    negatives: negatives.map(\.embedding),
    minimumPrecision: options.minimumPrecision
) else {
    fail("No usable faces in any reference photo.")
}

let genuine = zip(references, evaluation.genuineScores).map { Scored(file: $0.file, score: $1) }
let impostor = zip(negatives, evaluation.impostorScores).map { Scored(file: $0.file, score: $1) }

// MARK: Report and tune

func summarize(_ label: String, _ scores: [Scored]) {
    let sorted = scores.map(\.score).sorted()
    guard let lo = sorted.first, let hi = sorted.last else {
        print("  \(label): none")
        return
    }
    let median = sorted[sorted.count / 2]
    print("  \(label) (\(sorted.count)): min \(format(lo))  median \(format(median))  max \(format(hi))")
}

print("\nScores against the enrolled reference:")
summarize("her, leave-one-out", genuine)
summarize("other faces       ", impostor)

if !genuine.isEmpty {
    print("\nWeakest reference photos (consider replacing if far below the rest):")
    for s in genuine.sorted(by: { $0.score < $1.score }).prefix(3) {
        print("  \(format(s.score))  \(s.file)")
    }
}
if !impostor.isEmpty {
    print("\nMost similar other faces (the false positives to worry about):")
    for s in impostor.sorted(by: { $0.score > $1.score }).prefix(3) {
        print("  \(format(s.score))  \(s.file)")
    }
}

var exitCode: Int32 = 0
switch evaluation.outcome {
case .tuned(let result):
    print(String(
        format: "\nThreshold %.2f: precision %.3f, recall %.3f (%d TP, %d FP, %d FN)",
        result.threshold, result.precision, result.recall,
        result.truePositives, result.falsePositives, result.falseNegatives))
case .insufficientData:
    print("\nNot tuned: need at least 2 reference faces and at least 1 face in negatives/. "
        + "Enrollment written without a threshold; the app will use its default.")
    exitCode = 3
case .notDiscriminative:
    print("\nNo threshold reaches precision \(options.minimumPrecision). The reference set is "
        + "not discriminative enough. Add clearer, more varied photos of her, and check "
        + "negatives/ does not contain her. Enrollment written without a threshold.")
    exitCode = 2
}

try FileManager.default.createDirectory(
    at: options.output.deletingLastPathComponent(), withIntermediateDirectories: true)
try EnrollmentStore(fileURL: options.output)
    .save(Enrollment(embedderIdentifier: embedder.identifier, people: [evaluation.person]))
print("\nWrote \(options.output.path)")
exit(exitCode)
