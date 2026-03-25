# ADR 003: LLM-Powered Auto-Tagging

## Status

Proposed

## Context

Filechute's existing `TagSuggestionService` suggests tags based on filename
heuristics: file extension, MIME category, year-like tokens, and matches against
existing tags. This works for mechanical metadata but cannot infer semantic tags
from file content (e.g., recognizing that a PDF is an invoice, or that an image
contains a receipt).

Users currently assign tags manually during or after import. For large batches
this is tedious, and users may not think of all relevant tags up front.

An LLM can examine file content (text extraction, image recognition) alongside
the user's existing tag vocabulary and suggest semantically meaningful tags that
go beyond what filename parsing can provide.

## Decision

### User flow: import-time auto-tag review

When files are imported (via drag-and-drop, file picker, or paste), the app
presents a centered modal before completing ingestion. The modal shows one item
at a time:

1. **Preview pane** -- a thumbnail or QuickLook preview of the file.
2. **Suggested tags** -- LLM-generated suggestions displayed as toggleable
   chips, pre-selected. The user can deselect suggestions, type additional tags
   (with the existing autocomplete), or edit freely.
3. **Navigation controls**:
   - **Accept** (Return) -- applies the current tag selection and advances to
     the next item.
   - **Skip** -- skips this item (ingests it with no auto-tags, only the
     heuristic suggestions from `TagSuggestionService`) and advances.
   - **Skip All** (Shift+Return or button) -- skips all remaining items.
4. A progress indicator shows "Item 3 of 12" positioning.

Files are ingested into the object store before the modal appears (so previews
are available), but tags from the LLM review are applied only when the user
accepts them.

### User flow: retroactive auto-tagging

The same modal can be invoked on already-imported items by selecting one or more
items in the main view and pressing Cmd+Shift+T. The flow is identical except
that items already exist in the database; accepted tags are added to existing
tag sets.

### LLM integration: local model via llama.cpp

Run inference locally using a bundled or user-provided GGUF model through
`llama.cpp` (via its C API or the `swift-llama` Swift bindings). The reasons to
prefer local inference over a cloud API:

- **No API key management.** A "bring your own key" model adds onboarding
  friction, key storage concerns (Keychain, secure enclave), and runtime errors
  when keys expire or hit rate limits.
- **Privacy.** Filechute is a local-first document store. Sending file contents
  to a third-party API contradicts that principle. Users may store sensitive
  documents (tax returns, medical records, contracts) that should not leave the
  machine.
- **Offline operation.** Filechute works fully offline today. Cloud-dependent
  tagging would break that guarantee.
- **Cost.** No per-token charges. The user pays once (disk space for the model)
  and runs inference for free.

### Model selection and distribution

- **Default model**: A small multimodal model (e.g., LLaVA 7B Q4 quantization,
  ~4 GB) that can handle both text and image inputs. For text-only documents, a
  smaller text model (e.g., Phi-3 Mini, ~2 GB) may suffice.
- **Distribution**: The model is not bundled with the app binary. On first use
  of auto-tagging, the app prompts the user to download the model to
  `~/Library/Application Support/Filechute/models/`. A progress bar shows
  download status. The user can also point to an existing GGUF file.
- **Model management**: A preferences pane under Settings lists downloaded
  models and lets the user switch, delete, or add models.

### Prompt design

The LLM receives:

1. The file content (extracted text for documents, the image itself for images
   via multimodal input, filename and metadata for unsupported types).
2. The list of all existing tags in the user's database.
3. The heuristic suggestions from `TagSuggestionService`.
4. Instructions to return a JSON array of suggested tag strings, preferring
   existing tags when appropriate but also suggesting new ones.

Example system prompt:

```
You are a file tagging assistant. Given a file's content and metadata, suggest
relevant tags. Prefer tags from the existing list when they fit. You may suggest
new tags when none of the existing tags are appropriate. Return a JSON array of
tag strings, ordered by relevance. Limit to 5-8 tags.

Existing tags: ["invoice", "receipt", "tax", "2024", "medical", "pdf", ...]
Heuristic suggestions: ["pdf", "document", "2024"]
```

### Architecture

New components:

**`LLMService`** (`Sources/FilechuteCore/LLMService.swift`) -- manages model
loading, prompt construction, and inference. Exposes:

```swift
public func suggestTags(
    fileURL: URL,
    existingTags: [Tag],
    heuristicSuggestions: [String]
) async throws -> [String]
```

Runs inference on a background thread. Returns parsed tag suggestions.

**`ModelManager`** (`Sources/FilechuteCore/ModelManager.swift`) -- handles model
download, storage, and selection. Stores config in the database or a plist in
the app's Application Support directory.

**`AutoTagReviewView`** (`Sources/Filechute/AutoTagReviewView.swift`) -- the
modal view described above. Receives a list of items to review and yields
per-item tag decisions back to the caller.

**`TextExtractor`** (`Sources/FilechuteCore/TextExtractor.swift`) -- extracts
text content from documents using PDFKit (for PDFs), NSAttributedString (for
RTF/DOCX), or raw string reading (for plain text). Returns extracted text
truncated to the model's context window.

### Integration with existing code

- `StoreManager` orchestrates the flow: ingest files, then present
  `AutoTagReviewView` if auto-tagging is enabled.
- `LLMService` calls `TagSuggestionService.suggestTags()` to include heuristic
  suggestions in the prompt, combining both approaches.
- Existing `TagAutocompleteField` is reused in the review modal for manual tag
  entry.

### Performance considerations

- Model loading is done once and kept in memory for the session (LLaVA 7B Q4
  uses ~4-6 GB RAM). The model is unloaded after a period of inactivity.
- Inference for a single item takes 2-10 seconds on Apple Silicon depending on
  model size and input length. GPU acceleration via Metal is available through
  llama.cpp.
- While the user reviews item N, the app pre-fetches suggestions for item N+1
  in the background to minimize wait times.
- A loading spinner is shown while suggestions are being generated.

### Graceful degradation

- If no model is downloaded, auto-tagging falls back to
  `TagSuggestionService` heuristics only (current behavior).
- If inference fails for a specific file, the modal shows heuristic suggestions
  and a note that LLM suggestions are unavailable for this item.
- If the machine lacks sufficient RAM for the selected model, the app suggests
  a smaller quantization or model.

## Consequences

- Adds a dependency on `llama.cpp` (C library, compiled from source or via
  SPM). This is a significant new dependency but avoids any cloud service
  coupling.
- First-use requires a ~2-4 GB model download, which may surprise users. The
  download is optional and clearly communicated.
- RAM usage increases substantially when the model is loaded (~4-6 GB for a 7B
  model). This is acceptable on modern Macs (minimum 8 GB, commonly 16+) but
  should be clearly documented.
- Suggestion quality depends on the model. Smaller quantized models may produce
  less accurate suggestions than a cloud API like Claude, but the privacy and
  offline benefits outweigh this for Filechute's use case.
- The pre-fetching strategy keeps the review flow responsive despite per-item
  inference latency.

## Alternatives Considered

- **Cloud API with "bring your own key" (e.g., Anthropic Claude API)**: Better
  suggestion quality, especially for nuanced document understanding. But
  requires API key management (secure storage, rotation, error handling),
  breaks offline operation, sends potentially sensitive document content to a
  third party, and incurs per-use costs. The onboarding friction of obtaining
  and entering an API key is significant for a utility app. This option could
  be revisited as an opt-in alternative alongside local inference if users
  request higher-quality suggestions.
- **Apple Vision framework for image classification**: Free, on-device, and
  fast, but produces generic labels ("outdoor", "food") rather than
  user-vocabulary-aligned tags. Useful as a supplementary signal fed into the
  LLM prompt, but insufficient as the sole tagging mechanism.
- **Keyword extraction (TF-IDF, RAKE) without an LLM**: Fast and
  dependency-free for text documents, but cannot handle images, produces
  keywords rather than semantic tags, and cannot adapt to the user's existing
  tag vocabulary.
- **Apple's on-device Foundation Models framework (iOS 26 / macOS 26)**: Apple
  announced on-device LLM APIs at WWDC 2025. These would eliminate the
  llama.cpp dependency and model management burden, but require macOS 26 as
  the deployment target and the API surface may not support the prompt
  customization needed for structured tag output. Worth re-evaluating when
  macOS 26 ships and the API stabilizes, potentially replacing llama.cpp as
  the inference backend.
- **Hybrid approach (local model + cloud fallback)**: Adds complexity of
  maintaining two code paths. Defer to the simpler local-only approach first.
