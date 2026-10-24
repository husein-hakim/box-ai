#if os(iOS)
import Foundation
import CryptoKit
import TensorFlowLiteC

/// Unchanged shipped TFLite pose graph through official CPU/XNNPACK runtime.
/// Confined to one inference queue by its owner; never shared concurrently.
final class MoveNetRuntime {
    enum Model: String, Sendable {
        case thunder, lightning
        var filename: String { "movenet_\(rawValue)_fp16" }
        var sha256: String {
            switch self {
            case .thunder: "41641538679ec79b07d4101e591dda47d098c09af29607674b2a40b8a3798dd3"
            case .lightning: "0fac2226112d0371903ca86e3853cec24ef603a0b2f96f589b180f0ebdd135ab"
            }
        }
    }
    enum Failure: Error { case missingModel, modelHash, creation, contract, invoke, buffer }
    let model: Model
    let inputSize: Int
    let runtimeVersion: String
    private let modelHandle: OpaquePointer
    private let interpreter: OpaquePointer
    private let delegate: UnsafeMutablePointer<TfLiteDelegate>
    private let floatInput: Bool

    init(model: Model, threads: Int = 4, modelURL: URL? = nil) throws {
        guard threads > 0 && threads <= 8 else { throw Failure.contract }
        guard let url = modelURL ?? Bundle.main.url(forResource: model.filename, withExtension: "tflite") else { throw Failure.missingModel }
        let bytes = try Data(contentsOf: url)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard digest == model.sha256 else { throw Failure.modelHash }
        guard let handle = url.path.withCString({ TfLiteModelCreateFromFile($0) }) else { throw Failure.creation }
        guard let options = TfLiteInterpreterOptionsCreate() else { TfLiteModelDelete(handle); throw Failure.creation }
        var delegateOptions = TfLiteXNNPackDelegateOptionsDefault()
        delegateOptions.num_threads = Int32(threads)
        guard let xnn = TfLiteXNNPackDelegateCreate(&delegateOptions) else {
            TfLiteInterpreterOptionsDelete(options); TfLiteModelDelete(handle); throw Failure.creation
        }
        TfLiteInterpreterOptionsSetNumThreads(options, Int32(threads))
        TfLiteInterpreterOptionsAddDelegate(options, xnn)
        let created = TfLiteInterpreterCreate(handle, options)
        TfLiteInterpreterOptionsDelete(options)
        guard let instance = created else { TfLiteXNNPackDelegateDelete(xnn); TfLiteModelDelete(handle); throw Failure.creation }
        do {
            guard TfLiteInterpreterAllocateTensors(instance) == kTfLiteOk,
                  TfLiteInterpreterGetInputTensorCount(instance) == 1,
                  TfLiteInterpreterGetOutputTensorCount(instance) == 1,
                  let input = TfLiteInterpreterGetInputTensor(instance, 0),
                  let output = TfLiteInterpreterGetOutputTensor(instance, 0),
                  TfLiteTensorNumDims(input) == 4, TfLiteTensorDim(input, 0) == 1,
                  TfLiteTensorDim(input, 3) == 3, TfLiteTensorDim(input, 1) > 0,
                  TfLiteTensorDim(input, 1) == TfLiteTensorDim(input, 2),
                  TfLiteTensorType(input) == kTfLiteUInt8 || TfLiteTensorType(input) == kTfLiteFloat32,
                  TfLiteTensorType(output) == kTfLiteFloat32,
                  TfLiteTensorNumDims(output) == 4,
                  (0..<4).map({ TfLiteTensorDim(output, Int32($0)) }) == [1, 1, 17, 3] else { throw Failure.contract }
            self.model = model; self.modelHandle = handle; self.interpreter = instance; self.delegate = xnn
            self.inputSize = Int(TfLiteTensorDim(input, 1)); self.floatInput = TfLiteTensorType(input) == kTfLiteFloat32
            self.runtimeVersion = String(cString: TfLiteVersion())
        } catch {
            TfLiteInterpreterDelete(instance); TfLiteXNNPackDelegateDelete(xnn); TfLiteModelDelete(handle); throw error
        }
    }
    deinit { TfLiteInterpreterDelete(interpreter); TfLiteXNNPackDelegateDelete(delegate); TfLiteModelDelete(modelHandle) }

    func infer(rgb: Data, plan: MoveNetLetterbox) throws -> [MoveNetPoint] {
        guard plan.inputSize == inputSize, rgb.count == inputSize * inputSize * 3,
              let input = TfLiteInterpreterGetInputTensor(interpreter, 0) else { throw Failure.buffer }
        let copied: TfLiteStatus
        if floatInput {
            // Android copies RGB byte values into Float32 unchanged: no /255 normalization.
            let values = rgb.map(Float.init)
            copied = values.withUnsafeBytes { TfLiteTensorCopyFromBuffer(input, $0.baseAddress, $0.count) }
        } else { copied = rgb.withUnsafeBytes { TfLiteTensorCopyFromBuffer(input, $0.baseAddress, $0.count) } }
        guard copied == kTfLiteOk, TfLiteInterpreterInvoke(interpreter) == kTfLiteOk,
              let output = TfLiteInterpreterGetOutputTensor(interpreter, 0) else { throw Failure.invoke }
        var points = [Float](repeating: 0, count: 51)
        let status = points.withUnsafeMutableBytes { TfLiteTensorCopyToBuffer(output, $0.baseAddress, $0.count) }
        guard status == kTfLiteOk, points.allSatisfy(\.isFinite) else { throw Failure.buffer }
        return (0..<17).map { i in plan.sourcePoint(modelY: points[i * 3], modelX: points[i * 3 + 1], score: points[i * 3 + 2]) }
    }
}
#endif
