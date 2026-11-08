# Draft AI integration handoff

This branch adds an optional OpenAI API provider to Draft's existing Assistant and a read-only local MCP bridge for Codex. It was built from `main` while the v0.6 UI polish branch had uncommitted changes. Merge the polish work first, then resolve UI conflicts against this branch. The user's vault and the existing polish checkout were not edited.

## Implemented

- Assistant provider selector: local model remains the default; OpenAI is optional.
- API key stored in the macOS Keychain, never in `library.json` or the vault. Model ID is editable, initially `gpt-6.1-sol`.
- OpenAI Responses API streaming with `store: false`; the user reviews the exact selected context and prior turns before each request. Selection, Document and Space retrieval, source cards, Stop, and Insert/Replace preview reuse the existing flow. Local and cloud histories are separate per Space.
- A `DraftMCP` stdio executable exposes `draft_list_spaces`, `draft_list_documents`, `draft_search`, `draft_read_document`, and `draft_read_block`. It reads current-schema vault files directly without migration or writes. Trashed documents and templates are excluded.
- The MCP bridge is deliberately read-only. External write tools must go through running Draft's document command layer, show a scoped approval, and preserve undo, backups, IDs and link updates. Direct file writes from an external process would race Draft's autosave.

## Setup after merge

Build with `swift build --product DraftMCP`. Run `scripts/draft-mcp.sh` as a local stdio MCP server. The script writes build output only to stderr. A Codex configuration can point its command to the absolute path of this script. No global Codex config was modified by this branch.

The OpenAI option currently uses a user-supplied API key and the Responses API. It does **not** use the user's ChatGPT subscription or scrape Codex credentials. Sign in with ChatGPT for open-source apps and a Codex app-server driver are separate future work; re-check eligibility and current official docs before implementing them. Do not present this branch as a full Codex agent inside Draft.

## Checks and remaining work for Claude

Unit tests cover provider-separated histories, old-settings defaults, SSE parsing, request privacy fields, read-only vault access and trash filtering. `swift test` and a stdio protocol probe pass. A real OpenAI request was not made; it requires a user-owned key and explicit opt-in. The cloud panel needs visual review and polish after the v0.6 branch is merged.

Next steps:

1. Merge against the finished v0.6 UI work. Reconcile the Assistant, Settings, design-system and model changes rather than overwriting either branch.
2. Test the cloud mode with a throwaway vault and a real user-supplied key, including streaming, cancellation, error states, source cards, preview and undo. Check light/dark and narrow/floating layouts.
3. Add a genuine Codex app-server mode only after implementing a supported authentication flow, streaming protocol, cancellation, and explicit approval handling. Keep it distinct from OpenAI API chat in the UI.
4. Add app-mediated write tools and multi-step note operations with a reviewable proposed diff and one undo transaction. Avoid direct MCP writes to vault JSON.
5. Update roadmap, parity and privacy copy to describe the optional network path precisely. Keep the repo private until the user chooses otherwise.

Current reference docs: [Responses streaming](https://developers.openai.com/api/docs/guides/streaming-responses), [Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server), [Sign in with ChatGPT for open-source apps](https://developers.openai.com/siwc/quickstart).
