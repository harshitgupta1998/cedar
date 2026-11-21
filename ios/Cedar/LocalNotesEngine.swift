import Foundation
import llama

actor LocalNotesEngine {
    static let modelID = "SmolLM2-360M-Instruct-Q4_K_M"
    static let inputLimit = 3_500
    private static let initialized: Void = { llama_backend_init() }()

    func summarize(_ text: String, modelURL: URL) throws -> String {
        _ = Self.initialized
        try Task.checkCancellation()
        try NotesController.verifyModel(at: modelURL)
        var modelParameters = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
        #else
        modelParameters.n_gpu_layers = 99
        #endif
        guard let model = llama_model_load_from_file(modelURL.path, modelParameters) else { throw NotesError.loadFailed }
        defer { llama_model_free(model) }
        guard let vocabulary = llama_model_get_vocab(model) else { throw NotesError.loadFailed }
        // SmolLM2's published ChatML template. Escape control markers in source text.
        let source = text.replacingOccurrences(of: "<|", with: "< |")
        let prompt = """
        <|im_start|>system
        You are a helpful assistant that summarizes text accurately.
        <|im_end|>
        <|im_start|>user
        Write a brief factual summary of the following transcript in one paragraph. Preserve decisions and explicitly assigned tasks. Do not suggest new actions.
        
        Transcript:
        \(source)
        <|im_end|>
        <|im_start|>assistant
        
        """
        let needed = prompt.withCString { llama_tokenize(vocabulary, $0, Int32(prompt.utf8.count), nil, 0, true, true) }
        guard needed < 0, -needed <= Self.inputLimit else { throw NotesError.inputTooLong }
        var tokens = [llama_token](repeating: 0, count: Int(-needed))
        let count = prompt.withCString { input in
            tokens.withUnsafeMutableBufferPointer {
                llama_tokenize(vocabulary, input, Int32(prompt.utf8.count), $0.baseAddress, Int32($0.count), true, true)
            }
        }
        guard count > 0 else { throw NotesError.emptyResult }
        var parameters = llama_context_default_params()
        parameters.n_ctx = 4_096
        parameters.n_batch = 256
        parameters.n_ubatch = 256
        parameters.n_threads = Int32(min(4, max(1, ProcessInfo.processInfo.activeProcessorCount - 2)))
        parameters.n_threads_batch = parameters.n_threads
        guard let context = llama_init_from_model(model, parameters) else { throw NotesError.loadFailed }
        defer { llama_free(context) }
        guard let sampler = llama_sampler_init_greedy() else { throw NotesError.loadFailed }
        defer { llama_sampler_free(sampler) }
        // Small batches bound cancellation latency during prompt evaluation.
        for start in stride(from: 0, to: Int(count), by: 256) {
            try Task.checkCancellation()
            let length = min(256, Int(count) - start)
            let status = tokens.withUnsafeMutableBufferPointer {
                llama_decode(context, llama_batch_get_one($0.baseAddress!.advanced(by: start), Int32(length)))
            }
            guard status == 0 else { throw NotesError.loadFailed }
        }
        var bytes = [UInt8]()
        for _ in 0..<384 {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) {
                let output = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else { throw NotesError.emptyResult }
                return output
            }
            var piece = [CChar](repeating: 0, count: 256)
            var size = llama_token_to_piece(vocabulary, token, &piece, Int32(piece.count), 0, false)
            if size < 0 {
                piece = [CChar](repeating: 0, count: Int(-size))
                size = llama_token_to_piece(vocabulary, token, &piece, Int32(piece.count), 0, false)
            }
            guard size >= 0 else { throw NotesError.loadFailed }
            bytes.append(contentsOf: piece.prefix(Int(size)).map { UInt8(bitPattern: $0) })
            let status = withUnsafeMutablePointer(to: &token) { llama_decode(context, llama_batch_get_one($0, 1)) }
            guard status == 0 else { throw NotesError.loadFailed }
        }
        throw NotesError.outputTooLong
    }
}
