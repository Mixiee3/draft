import Foundation
import llama
@_exported import DraftCore

public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    public func cancel() { lock.lock(); value = true; lock.unlock() }
}

public struct GenerationStats: Sendable, Equatable {
    public var promptTokens = 0
    public var generatedTokens = 0
    public var firstTokenSeconds = 0.0
    public var tokensPerSecond = 0.0
    public var cancelled = false
    public init() {}
}

public enum EngineError: LocalizedError, Equatable {
    case notEnoughMemory(needed: UInt64, physical: UInt64)
    case loadFailed(String)
    case promptTooLong(tokens: Int, limit: Int)
    case decodeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .notEnoughMemory(let n, let p): return "This Mac has \(p >> 30) GB of memory; the model needs at least \(n >> 30) GB. Choose the smaller model in Settings → Assistant."
        case .loadFailed(let s): return "The model could not be loaded (\(s)). Remove it in Settings → Assistant and download it again."
        case .promptTooLong(let t, let l): return "The request is \(t) tokens, more than the model's \(l)-token window. Choose a smaller context."
        case .decodeFailed(let c): return "The model stopped with an error (\(c)). Try again."
        }
    }
}

/// Produces text from a conversation. The real engine runs llama.cpp; tests use stand-ins.
public protocol TextGenerator: AnyObject {
    var contextTokens: Int { get }
    func countTokens(_ text: String) -> Int
    func generate(_ turns: [ChatTurn], maxTokens: Int, cancel: CancelFlag, onPiece: (String) -> Void) throws -> GenerationStats
}

private func quietLog(_: ggml_log_level, _: UnsafePointer<CChar>?, _: UnsafeMutableRawPointer?) {}

/// llama.cpp on Metal, entirely in this process. Call from one background thread at a time.
public final class LlamaEngine: TextGenerator {
    private let model: OpaquePointer
    private let vocab: OpaquePointer
    private let ctx: OpaquePointer
    public let contextTokens: Int
    private let template: String?

    public init(path: URL, minimumMemory: UInt64, contextTokens: Int = 8192) throws {
        guard SystemMemory.physical >= minimumMemory else { throw EngineError.notEnoughMemory(needed: minimumMemory, physical: SystemMemory.physical) }
        llama_log_set(quietLog, nil)
        llama_backend_init()
        var mp = llama_model_default_params()
        mp.n_gpu_layers = 999
        guard let m = llama_model_load_from_file(path.path, mp) else { throw EngineError.loadFailed("unreadable model file") }
        var cp = llama_context_default_params()
        cp.n_ctx = UInt32(contextTokens)
        cp.n_batch = 512
        guard let c = llama_init_from_model(m, cp) else { llama_model_free(m); throw EngineError.loadFailed("no memory for the context") }
        model = m; ctx = c; vocab = llama_model_get_vocab(m)
        self.contextTokens = contextTokens
        template = llama_model_chat_template(m, nil).map { String(cString: $0) }
    }

    deinit { llama_free(ctx); llama_model_free(model) }

    public func countTokens(_ text: String) -> Int { tokenize(text, special: false).count }

    func tokenize(_ text: String, special: Bool) -> [llama_token] {
        let n = Int32(text.utf8.count) + 8
        var out = [llama_token](repeating: 0, count: Int(n))
        var k = llama_tokenize(vocab, text, Int32(text.utf8.count), &out, n, false, special)
        if k < 0 { out = [llama_token](repeating: 0, count: Int(-k)); k = llama_tokenize(vocab, text, Int32(text.utf8.count), &out, -k, false, special) }
        return Array(out.prefix(Int(max(0, k))))
    }

    /// ChatML as the model's own template expects; built directly when llama.cpp can't apply it.
    func format(_ turns: [ChatTurn]) -> String {
        if let template {
            var cStrings: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] = turns.map { (strdup($0.role)!, strdup($0.text)!) }
            defer { cStrings.forEach { free($0.0); free($0.1) } }
            let msgs = cStrings.map { llama_chat_message(role: $0.0, content: $0.1) }
            var buf = [CChar](repeating: 0, count: turns.reduce(256) { $0 + $1.text.utf8.count * 2 })
            var n = llama_chat_apply_template(template, msgs, msgs.count, true, &buf, Int32(buf.count))
            if n > buf.count { buf = [CChar](repeating: 0, count: Int(n) + 1); n = llama_chat_apply_template(template, msgs, msgs.count, true, &buf, Int32(buf.count)) }
            if n > 0 { return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        }
        return "<|startoftext|>" + turns.map { "<|im_start|>\($0.role)\n\($0.text)<|im_end|>\n" }.joined() + "<|im_start|>assistant\n"
    }

    public func generate(_ turns: [ChatTurn], maxTokens: Int, cancel: CancelFlag, onPiece: (String) -> Void) throws -> GenerationStats {
        var stats = GenerationStats()
        let text = format(turns)
        var tokens = tokenize(text.hasPrefix("<|startoftext|>") ? text : "<|startoftext|>" + text, special: true)
        stats.promptTokens = tokens.count
        guard tokens.count + 16 < contextTokens else { throw EngineError.promptTooLong(tokens: tokens.count, limit: contextTokens) }
        llama_memory_clear(llama_get_memory(ctx), true)
        let flag = Unmanaged.passUnretained(cancel).toOpaque()
        llama_set_abort_callback(ctx, { data in Unmanaged<CancelFlag>.fromOpaque(data!).takeUnretainedValue().isCancelled }, flag)
        defer { llama_set_abort_callback(ctx, nil, nil) }

        let start = Date()
        var i = 0
        while i < tokens.count {
            let end = min(tokens.count, i + 512)
            let r = tokens.withUnsafeMutableBufferPointer { llama_decode(ctx, llama_batch_get_one($0.baseAddress! + i, Int32(end - i))) }
            if cancel.isCancelled { stats.cancelled = true; return stats }
            guard r == 0 else { throw EngineError.decodeFailed(r) }
            i = end
        }

        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        defer { llama_sampler_free(chain) }
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.1, 0, 0))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(50))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.1))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

        var pending: [UInt8] = []
        var genStart = Date()
        let budget = min(maxTokens, contextTokens - tokens.count - 1)
        while stats.generatedTokens < budget {
            if cancel.isCancelled { stats.cancelled = true; break }
            var tok = llama_sampler_sample(chain, ctx, -1)
            if llama_vocab_is_eog(vocab, tok) { break }
            if stats.generatedTokens == 0 { stats.firstTokenSeconds = Date().timeIntervalSince(start); genStart = Date() }
            stats.generatedTokens += 1
            var buf = [CChar](repeating: 0, count: 64)
            let n = llama_token_to_piece(vocab, tok, &buf, 64, 0, false)
            if n > 0 { pending += buf.prefix(Int(n)).map { UInt8(bitPattern: $0) } }
            if let s = String(validatingUTF8Prefix: &pending), !s.isEmpty { onPiece(s) }
            let r = llama_decode(ctx, llama_batch_get_one(&tok, 1))
            if cancel.isCancelled { stats.cancelled = true; break }
            guard r == 0 else { throw EngineError.decodeFailed(r) }
        }
        if !pending.isEmpty { onPiece(String(decoding: pending, as: UTF8.self)) }
        let secs = Date().timeIntervalSince(genStart)
        stats.tokensPerSecond = secs > 0 ? Double(max(0, stats.generatedTokens - 1)) / secs : 0
        tokens.removeAll()
        return stats
    }
}

extension String {
    /// Takes the longest complete UTF-8 prefix of `bytes`, leaving a split character behind.
    init?(validatingUTF8Prefix bytes: inout [UInt8]) {
        var cut = bytes.count
        while cut > 0, cut > bytes.count - 4 {
            if let s = String(bytes: bytes.prefix(cut), encoding: .utf8) { bytes.removeFirst(cut); self = s; return }
            cut -= 1
        }
        return nil
    }
}
