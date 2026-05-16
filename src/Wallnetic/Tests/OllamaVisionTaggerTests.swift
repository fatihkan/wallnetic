import XCTest
@testable import Wallnetic

/// Tests cover the pure parsing surface of OllamaVisionTagger (#116). The
/// network path is intentionally not exercised here — its only contract is
/// "fail soft when Ollama is offline", and that already returns nil via the
/// catch path. We verify the JSON contract that lives between Ollama and us.
final class OllamaVisionTaggerTests: XCTestCase {

    // MARK: - Plain JSON response

    func test_parseTags_extracts_array_from_clean_json() {
        let payload = """
        {"tags": ["nature", "sunrise", "mountain"]}
        """
        let tags = OllamaVisionTagger.parseTags(fromText: payload)
        XCTAssertEqual(tags, ["mountain", "nature", "sunrise"], "Should be deduped + sorted.")
    }

    // MARK: - JSON wrapped in prose

    func test_parseTags_extracts_array_when_model_prepended_prose() {
        let payload = """
        Sure! Here are the tags I found:

        {"tags": ["anime", "city"]}

        Hope this helps!
        """
        XCTAssertEqual(OllamaVisionTagger.parseTags(fromText: payload), ["anime", "city"])
    }

    // MARK: - Markdown fences

    func test_parseTags_extracts_array_from_markdown_fenced_json() {
        let payload = """
        ```json
        {"tags": ["abstract", "neon"]}
        ```
        """
        XCTAssertEqual(OllamaVisionTagger.parseTags(fromText: payload), ["abstract", "neon"])
    }

    // MARK: - Dirty tags

    func test_parseTags_cleans_quotes_and_lowercases() {
        let payload = """
        {"tags": ["\\"Nature\\"", "Sunrise.", "  Mountain  "]}
        """
        let tags = OllamaVisionTagger.parseTags(fromText: payload)
        XCTAssertEqual(tags, ["mountain", "nature", "sunrise"])
    }

    func test_parseTags_drops_overlong_garbage() {
        let payload = """
        {"tags": ["ok", "this-tag-is-way-way-way-way-too-long-and-should-be-rejected-by-the-cleaner"]}
        """
        XCTAssertEqual(OllamaVisionTagger.parseTags(fromText: payload), ["ok"])
    }

    // MARK: - Malformed input

    func test_parseTags_returns_nil_when_no_json() {
        XCTAssertNil(OllamaVisionTagger.parseTags(fromText: "Sorry, I cannot analyze this image."))
    }

    func test_parseTags_returns_nil_when_tags_missing() {
        XCTAssertNil(OllamaVisionTagger.parseTags(fromText: #"{"other": ["nope"]}"#))
    }

    func test_parseTags_returns_nil_for_empty_string() {
        XCTAssertNil(OllamaVisionTagger.parseTags(fromText: ""))
    }

    // MARK: - Full /api/generate response shape

    func test_parseTags_fromResponseData_handles_ollama_reply_envelope() {
        let envelope = """
        {
            "model": "llava",
            "created_at": "2026-05-16T12:00:00Z",
            "response": "{\\"tags\\": [\\"forest\\", \\"green\\"]}",
            "done": true
        }
        """
        let data = envelope.data(using: .utf8)!
        XCTAssertEqual(OllamaVisionTagger.parseTags(fromResponseData: data), ["forest", "green"])
    }

    func test_parseTags_fromResponseData_returns_nil_for_non_json_envelope() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(OllamaVisionTagger.parseTags(fromResponseData: data))
    }

    // MARK: - cleanTag

    func test_cleanTag_strips_punctuation_and_whitespace() {
        XCTAssertEqual(OllamaVisionTagger.cleanTag("  \"Nature.\" "), "nature")
        XCTAssertEqual(OllamaVisionTagger.cleanTag("#anime;"), "anime")
    }

    func test_cleanTag_rejects_empty_and_overlong() {
        XCTAssertNil(OllamaVisionTagger.cleanTag(""))
        XCTAssertNil(OllamaVisionTagger.cleanTag(String(repeating: "x", count: 50)))
    }
}
