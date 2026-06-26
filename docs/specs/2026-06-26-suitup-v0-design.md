# SuitUp v0 — Personal AI Styling App

**Status:** Design — approved scope, awaiting user review
**Date:** 2026-06-26
**Owner:** Finn Sommer
**Scope:** Option X (personal app, scope-locked). See `project_suitup_roadmap.md` in memory for the broader "Social Shopping Mirror" vision deferred to post-v0.

---

## 1. Vision & Wedge

**One-liner:** A personal native iOS app where Finn manages his closet and gets AI-grounded outfit suggestions, primarily by tapping a piece he owns and asking *"what goes with this?"*

**Why this wedge:** The "style what I own" question repeats daily. AI-grounded suggestions from a curated reference taste-anchor + Finn's actual closet items + saved outfits compound in personalization over time. No cold-start problem after the first ~20 references.

**Out of scope (deferred to roadmap):** Multi-user, social, affiliate, virtual try-on, AR, brand partnerships, loyalty tiers, Pro subscription, weather/calendar context, "haven't worn in X days," shop integration.

---

## 2. Platform & Stack

| Layer | Choice | Why |
|---|---|---|
| App | Native iOS, Swift + SwiftUI | Best access to iOS Vision (bg-removal), Share Sheet target, camera/PhotoKit. SwiftUI is the modern path. Finn will use Xcode. |
| Min iOS | iOS 17.0 | Required for `VNGenerateForegroundInstanceMaskRequest` (built-in subject lift). |
| Local storage | SwiftData (Core Data successor) | First-class SwiftUI binding, no boilerplate. Schema migrations supported. |
| Local files | iOS sandbox `Application Support/items/`, `references/`, `outfits/` | Images stored as JPEG (compressed to ~1024px long edge). Original kept only when user explicitly enables (post-v0). |
| Backend (single concern in v0) | Cloudflare Worker | URL crawling endpoint. No DB, no auth. ~50–100 lines of TS. Reuses Finn's existing Cloudflare account. |
| AI | Anthropic Claude (Sonnet 4.6) via REST API, called directly from the iOS app using a user-provided API key | Vision-capable, strong at structured JSON output, Finn already familiar. Key stored in iOS Keychain. |
| Image background removal | iOS Vision framework, on-device | Free, fast, no network. |
| Crawler fallback model | Same Claude Sonnet 4.6 (vision) via Worker | One vendor for AI calls keeps things simple. |
| Auth | None | Personal device, single user. |
| Sync / cloud storage | Not in v0 | Documented migration path: iCloud (CloudKit) for personal sync, or Supabase if Option Y becomes real. |

**Why not Cloudflare for image storage in v0:** Local-only is simpler. Phone has plenty of space for ~200 items × ~200 KB each = ~40 MB. Adding R2 sync now solves a problem we don't have yet.

**Migration paths (documented, not implemented):**
- Personal sync across Finn's devices → CloudKit (native, free, easiest)
- Multi-user (Option Y) → Supabase (Postgres + auth + realtime)
- Either migration is bounded: small data model (5 entities), <1 day work.

---

## 3. Navigation & Top-Level Screens

Bottom tab bar, 4 tabs:

1. **Closet** — your items, organized by category rails. Default tab.
2. **Outfits** — saved outfits, both manually built and saved from styling suggestions.
3. **References** — taste-anchor mood board.
4. **Recreate** — history of recreate attempts; entry point for new ones.

Settings: gear icon in top-right of Closet tab.

---

## 4. Data Model

Five entities, plus event logs.

### `Item` (closet piece)
```
id              UUID
imagePath       string (local file path to bg-removed JPEG)
originalImagePath  string (local path to original capture/download)
thumbnailPath   string (256px)
additionalImagePaths  [string]  // up to 3 total (1 primary + 2 secondary)
source          enum { photo, urlCrawl }
sourceUrl       string?
name            string
category        enum { top, bottom, outerwear, footwear, accessory, fullBody }
subcategory     string  (e.g. "T-shirt", "Dress shirt", "Chinos")
colors          [string]  (primary + optional secondary)
formality       enum { casual, smartCasual, formal, sportswear }
seasons         [enum]   { spring, summer, autumn, winter }
pattern         string?  (solid, striped, plaid, …)
material        string?  (marked as guess if from vision)
brand           string?
size            string?
fit             enum?    { loose, regular, slim, tailored }
occasionTags    [string] (work, casual, gym, going-out, …)
purchaseDate    Date?
price           Decimal?
purchasedFrom   string?  (domain)
notes           string?
createdAt       Date
updatedAt       Date
```

### `Outfit`
```
id              UUID
name            string
itemIds         [UUID]  (ordered: top first, then bottom, etc.)
coverImagePath  string  (auto-generated flat-lay collage)
source          enum { manuallyBuilt, savedFromStyling }
rationale       string?  (preserved when saved from AI suggestion)
notes           string?
createdAt       Date
updatedAt       Date
```

### `ReferenceLook`
```
id              UUID
imagePath       string  (local, ~1024px long edge)
thumbnailPath   string  (256px)
source          enum { library, urlCrawl, shareSheet }
sourceUrl       string?
note            string?
createdAt       Date
```

### `RecreateAttempt`
```
id                       UUID
sourceImagePath          string
sourceUrl                string?
parsedPieces             [ParsedPiece]
matches                  [PieceMatch]
recreatableCount         int
totalPieceCount          int
linkedReferenceLookId    UUID?  (if saved as reference too)
createdAt                Date

ParsedPiece (embedded):
  description   string
  category      enum
  colors        [string]
  formality     enum?

PieceMatch (embedded):
  pieceDescription   string
  status             enum { matched, missing }
  matchedItemId      UUID?
  matchConfidence    enum? { veryClose, close, loose }
  matchNote          string?
  wantedPieceId      UUID?   (only if status=missing and user tapped "save as want")
```

### `WantedPiece`
```
id                       UUID
description              string
category                 enum
colors                   [string]
sourceRecreateAttemptId  UUID
createdAt                Date
```

### Event logs (lightweight)

```
WearEvent { id, itemId?, outfitId?, timestamp }
StylingRequest { id, itemId, contextOccasion?, contextWeather?,
                 closetSnapshotIds: [UUID], suggestionsReturned: [Outfit-shape],
                 timestamp, modelCostUSD }
```

`StylingRequest` is for debugging + future personalization learning.

---

## 5. The Five Flows

### Flow 1 — Add item via photo

**Entry:** Closet tab → `+` → "Take photo" or "Pick from library"

**Sequence:**
1. Capture/pick image
2. Run iOS Vision `VNGenerateForegroundInstanceMaskRequest` → bg-removed JPEG saved
3. Send bg-removed image to Claude Sonnet vision with structured-output prompt → returns name, category, subcategory, colors, formality, seasons, pattern, material guess, fit, occasion tags
4. Show confirm screen with all fields editable
5. User can add up to 2 more photos (back, detail)
6. Save → Item written to SwiftData

**Edge cases:** offline (save untagged, queue tagging), garbage response (fallback to manual), non-clothing detection.

### Flow 2 — Add item via URL

**Entry:** Closet `+` → "Paste link", **or** iOS Share Sheet from any browser/IG/Pinterest product page → SuitUp.

**Sequence:**
1. User submits URL (or shares URL from another app)
2. App POSTs URL to Cloudflare Worker `/crawl`
3. Worker fetches the page, tries JSON-LD / OpenGraph extraction first
4. If essential fields missing: Worker downloads the top-N candidate product images from the page and sends them + page `<title>`, meta description, and visible text to Claude vision for extraction. (No headless-browser screenshot — Cloudflare Workers can't run a browser. Image-based fallback is sufficient.)
5. Worker returns: `{ images: [urls], name, brand, price, color, material, sizes, … }`
6. App downloads selected image, runs bg-removal locally
7. Show same confirm screen as Flow 1, pre-filled
8. Clarifying questions only for essential gaps (most common: size purchased)
9. Save → Item

**Worker contract:**
```
POST /crawl
Body: { url: string }
Response: {
  success: bool,
  images: [string],          // CDN URLs from the source
  data: {
    name?: string,
    brand?: string,
    price?: { value: number, currency: string },
    colors?: [string],
    materials?: [string],
    availableSizes?: [string],
    category?: string,
    description?: string
  },
  warnings: [string]         // e.g. "size not detected, ask user"
}
```

**Worker secret:** Anthropic API key stored as Cloudflare Worker secret (used by the vision fallback). This is *separate* from the user-side Anthropic key in the iOS app — the Worker pays its own AI costs, which is fine because crawl frequency is low and per-call cost is tiny.

**Edge cases:** 404, blocked sites, paywalls, non-product pages, URL is actually an outfit (route to Flow 5).

### Flow 3 — Add reference look

**Entry:** References tab → `+`, or Share Sheet (image received).

**Sequence:**
1. User provides image (library / URL / share)
2. Resize to ~1024px long edge (preserve aspect ratio), generate 256px thumbnail
3. Optional note field
4. Save → ReferenceLook

No tags. Image-only by design. Vision model reads the image at request time.

**Note:** References are a *global taste anchor*. They are NOT auto-checked for recreatability when saved (Flow 5 does that on demand).

### Flow 4 — Style this piece

**Entry:** Tap any item in Closet → item detail → "Style this piece" CTA.

**Pre-AI step (instant):** Filter saved Outfits where `itemIds` contains this item's id → show as "You've worn this with" section.

**AI step:**
1. Build payload:
   - Selected item: image + tags
   - Closet subset: send all items in non-conflicting categories. Conflicting = same primary slot. Concretely: if selected is a `top`, exclude all other items where `category=top`; include everything else. Same for `bottom`. If selected is `outerwear`, include other categories but allow up to 1 alternative outerwear piece for layered looks. Footwear and accessories are never excluded. Cap at 30 items total — if closet is larger, prioritize recency + matching `formality`/`seasons` to the selected piece.
   - Saved outfits containing this item: up to 5
   - Reference looks: up to 10 most recent (configurable)
2. POST to Anthropic Messages API with the payload + system prompt (see §6)
3. Receive structured JSON: 3 outfit suggestions, each `{ itemIds: [UUID], rationale: string, name: string }`
4. **Validate**: every returned `itemId` must exist in the closet snapshot we sent. Reject hallucinated items. If <2 valid suggestions, retry once with stricter prompt.
5. For each valid suggestion: build collage (see §7), render result card

**No context selectors in v0** (no occasion/weather inputs). Tap → generate.

**Result card actions:** Save outfit, Wore today, tap item to open its detail.

**Refresh `↻`:** Re-run AI, passing a `previouslySuggestedItemSets: [[UUID]]` field to bias toward novelty.

**Cost:** ~30 images per request × Sonnet vision pricing ≈ €0.10–0.20 per request.

### Flow 4b — Save outfit

**Entry sources:**
- "Save outfit" on a styling suggestion → Outfit created from suggestion's `itemIds`, `rationale` preserved, `source = savedFromStyling`
- "+ New outfit" in Outfits tab → manual builder (pick 2-6 items via filtered closet view), name it, save

**Cover image:** Auto-generated flat-lay collage of the items' bg-removed images, arranged top→bottom by category order, saved as `coverImagePath`.

### Flow 5 — Recreate this look

**Entry:** Recreate tab → `+`, or Share Sheet (image received → user picks "Recreate" vs "Save as reference").

**Sequence:**
1. User provides outfit image (library / URL / share)
2. Build single AI call payload:
   - Reference outfit image
   - Closet inventory: ALL items (no category filter — we don't know what's in the look yet), with item IDs
   - Reference looks: 5 most recent (for taste context)
3. System prompt: parse the look + match against closet in one response (see §6)
4. Response shape:
   ```json
   {
     "parsedPieces": [
       { "description": "white boxy crew tee", "category": "top",
         "colors": ["white"], "formality": "casual" },
       ...
     ],
     "matches": [
       { "pieceIndex": 0, "status": "matched", "itemId": "...",
         "confidence": "veryClose", "note": "Same silhouette and color" },
       { "pieceIndex": 2, "status": "missing",
         "note": "No olive utility overshirt in closet" }
     ]
   }
   ```
5. **Validate** itemIds against closet snapshot; ignore matches referencing non-existent items
6. Render results screen (§4 mockups in brainstorm session)

**Actions per result:**
- "Save as want" on a missing piece → WantedPiece created
- "Save as outfit (matched only)" → Outfit created from matched items
- "Save as reference" → ReferenceLook created from the source image
- Tap a matched item → opens its Closet detail

### Auxiliary flows (smaller, no full breakdown needed)

- **Browse closet** — Category Rails (Netflix-style horizontal scroll per category). Filter chips above. Tap → item detail.
- **Item detail** — Large image, all tags shown, edit/replace/delete actions, "Style this piece" CTA, list of outfits containing this item.
- **Settings** — Anthropic API key (stored in Keychain), data export (JSON), clear-all-data with confirm, app info.
- **First launch** — Cold open. Empty closet, visible `+`. No tutorial.
- **Wishlist** — Surfaced as a section in the Recreate tab (list of WantedPieces).

---

## 6. AI Prompts (high-level)

All AI calls use Claude Sonnet 4.6 with structured JSON output enforced via tool-use schema.

**Common context blocks:**
- "You are a stylist for one specific person. Their taste anchor is shown via reference images. Their closet inventory is shown with item IDs you must use exactly."
- Reference looks block: up to 10 images, no captions ("These represent the user's aesthetic")
- Closet inventory block: each item shown as `<id>: [image, name, category, colors, formality, seasons]`

**Style-this-piece prompt skeleton:**
```
[system]
You are a personal stylist. Your job: suggest 3 outfits that include
the selected piece, using ONLY items from the provided closet inventory.

Rules:
- Each outfit must include 3-5 items total (including the selected piece)
- Use itemIds from the closet inventory — never invent items
- Each outfit must be distinct
- Lean toward the aesthetic of the reference looks
- Provide a 1-2 sentence rationale per outfit

[user content]
SELECTED PIECE: <image, tags>
REFERENCE LOOKS: <images>
CLOSET INVENTORY (compatible categories): <id+image+tags list>
SAVED OUTFITS WITH THIS PIECE: <collages of up to 5>
PREVIOUSLY SUGGESTED COMBOS (avoid): <list of itemId arrays>

[expected tool call]
suggest_outfits({
  outfits: [
    { name: string, itemIds: [string], rationale: string },
    ...
  ]
})
```

**Recreate prompt skeleton:**
```
[system]
You are a personal stylist. Your job: parse an outfit shown in a reference
image into its constituent pieces, then find the closest match in the
user's closet inventory for each piece (or mark missing).

Rules:
- Focus on primary pieces: top, bottom, outerwear, shoes, hero accessory
- For each piece, either match to an itemId from the inventory OR mark missing
- Match confidence: veryClose | close | loose
- Use only itemIds from the provided inventory

[user content]
REFERENCE OUTFIT: <image>
CLOSET INVENTORY (all categories): <id+image+tags list>
REFERENCE LOOKS (taste context): <up to 5 images>

[expected tool call]
parse_and_match({
  parsedPieces: [{description, category, colors, formality?}],
  matches: [{pieceIndex, status, itemId?, confidence?, note?}]
})
```

**Auto-tag-photo prompt skeleton:**
```
[system]
Identify the clothing piece in this image. Return structured tags.

Rules:
- Mark material as a guess
- If image is not clothing, return category="not-clothing"
- Use null for fields you cannot determine confidently

[expected tool call]
tag_item({
  name, category, subcategory, colors, formality, seasons,
  pattern?, material?, fit?, occasionTags
})
```

---

## 7. Collage Rendering

Programmatic flat-lay, no AI image generation in v0.

**Algorithm (SwiftUI Canvas or `ImageRenderer`):**
1. Get items sorted by category order: outerwear → top → bottom → footwear → accessories
2. Load each item's bg-removed image
3. Lay out on a 4:5 portrait canvas with light cream background:
   - Outerwear: top-left if present, otherwise hidden
   - Top: top-center
   - Bottom: middle-center
   - Footwear: bottom-center
   - Accessories: scattered top-right
4. Render to JPEG, save as outfit `coverImagePath`

Result is consistent, fast, and looks intentional. Replaced by AI-generated collages in roadmap.

---

## 8. iOS Integration Specifics

**Share Extension target:**
- Accepts: images (UTType.image) and URLs (UTType.url)
- On invocation, immediately presents a chooser:
  - For images: "Add as reference" / "Recreate this look"
  - For URLs: app fetches via Worker → classifies as "product page" or "outfit page" → "Add to closet" / "Recreate" / "Save as reference"
- Writes received payload into a shared App Group container, main app picks it up on next launch / via deep link

**Background removal:**
- `VNGenerateForegroundInstanceMaskRequest` on photo capture
- User can revert to original via a toggle on the confirm screen

**Camera & PhotoKit:**
- Standard `PHPickerViewController` for library
- `AVCaptureSession` wrapped in SwiftUI for camera; auto-focus, single-shot, no video

**Keychain:**
- Anthropic API key stored via `kSecClassGenericPassword`
- App refuses to call AI flows without it (clear surfaced error linking to Settings)

---

## 9. Cloudflare Worker

**Endpoint:** `POST /crawl`

**Implementation outline (TypeScript):**
```
1. Validate input URL, reject if not http(s)
2. Fetch the URL with a realistic User-Agent
3. Parse HTML, extract:
   - <script type="application/ld+json"> (Product schema if present)
   - <meta property="og:*">
   - <meta name="twitter:*">
   - <img> candidates (filtered by size hints)
4. If extraction is "good enough" (has name + ≥1 image + category):
   return { success: true, ... }
5. Else fall back to Claude Sonnet vision:
   - Fetch the top-N candidate product images (by alt text, og:image, largest declared dimensions)
   - Send those images + page title + meta description + visible text body to Claude
   - Ask Claude to extract product details
6. Return merged data
```

**Secrets (Wrangler):** `ANTHROPIC_API_KEY`

**Rate limiting:** Cloudflare's free tier handles this; no explicit limits needed at v0 scale (you'll crawl ~1-3 URLs/week).

**Deployment:** Worker lives in `~/Claude/suitup/worker/`. Deployed via `wrangler deploy`. URL: TBD (e.g., `suitup-crawler.<finn>.workers.dev`).

---

## 10. Error Handling Philosophy

- **Network failures**: never silent. Show clear retry. Preserve user state (don't lose photos / inputs).
- **AI failures**: validate every response. Reject hallucinations. Surface honestly: "We couldn't generate good suggestions — try again or change the piece."
- **Worker failures (Flow 2)**: offer fallback to manual photo entry without leaving the flow.
- **Missing API key**: hard-block AI features with a "Go to Settings" CTA. Non-AI features (browse closet, manually save outfits) continue working.

---

## 11. Testing Approach

- **Unit tests**: SwiftData models, prompt builders, response validators, collage layout logic
- **Snapshot tests**: closet rails, item detail, recreate results screen
- **Integration**: mock Anthropic responses for the styling and recreate flows; verify validation rejects hallucinated itemIds
- **Manual**: real Anthropic calls on a test closet of ~15 items, end-to-end through each flow

No CI in v0 — Finn runs tests locally before committing.

---

## 12. Project Structure

```
~/Claude/suitup/
├── docs/
│   └── specs/
│       └── 2026-06-26-suitup-v0-design.md   ← this file
├── ios/
│   ├── SuitUp.xcodeproj
│   ├── SuitUp/                    ← main app target
│   │   ├── App/
│   │   ├── Features/
│   │   │   ├── Closet/
│   │   │   ├── Outfits/
│   │   │   ├── References/
│   │   │   ├── Recreate/
│   │   │   ├── Styling/
│   │   │   ├── ItemCapture/
│   │   │   └── Settings/
│   │   ├── Models/                ← SwiftData entities
│   │   ├── Services/
│   │   │   ├── AnthropicClient.swift
│   │   │   ├── CrawlerClient.swift
│   │   │   ├── BackgroundRemoval.swift
│   │   │   ├── CollageRenderer.swift
│   │   │   └── KeychainStore.swift
│   │   └── Resources/
│   ├── SuitUpShareExtension/      ← share sheet target
│   └── SuitUpTests/
└── worker/
    ├── src/index.ts
    ├── wrangler.toml
    └── package.json
```

---

## 13. v0 Definition of Done

The app is "v0 done" when Finn can, on his own iPhone:

1. Add ≥30 items to closet via photo (Flow 1)
2. Add ≥5 items via URL crawl from at least 2 different retailers (Flow 2)
3. Add ≥15 reference looks (Flow 3)
4. Tap any closet item and get ≥3 AI-generated outfit suggestions where every suggested item exists in his closet (Flow 4) — primary success criterion
5. Save ≥10 outfits across manual and from-suggestion (Flow 4b)
6. Recreate ≥3 looks from Pinterest/IG via share sheet with honest matched/missing output (Flow 5)
7. The Share Sheet integration works from Safari, IG, and Pinterest

No app store submission. No TestFlight (unless Finn wants to install via TestFlight for convenience). Build runs from Xcode → Finn's iPhone via a free Apple Developer account.

---

## 14. Known Unknowns (worth flagging)

- **Claude vision cost at scale**: estimates above (€0.10–0.20 per styling) are based on input image count; final cost depends on Anthropic's pricing structure for many small images vs one large one. Will need a real measurement after the first 10 styling requests.
- **iOS share sheet image fidelity**: when IG shares an image to a target, sometimes it shares a low-res thumbnail rather than the full image. Need to verify and document workaround (e.g., open IG → tap "..." → "Copy link" → paste into SuitUp as fallback).
- **JSON-LD coverage on European fashion retailers**: most major ones do this well, but the long tail (small boutiques) will fall back to vision. Acceptable.
- **Background removal quality on busy backgrounds**: iOS Vision is good but not perfect. Acceptable for v0; user can revert to original.

---

## 15. What we're NOT doing (worth being explicit)

- ❌ Multi-device sync (defer to CloudKit later if needed)
- ❌ Image generation for outfit visualization (programmatic collage only)
- ❌ Weather/calendar integration
- ❌ "Haven't worn in X days" tracking surface (data is logged via WearEvent for future)
- ❌ Shop integration / affiliate / "buy this missing piece"
- ❌ Try-on / avatar / AR
- ❌ Social feed / creator content
- ❌ Loyalty/Club tiers
- ❌ Pro subscription
- ❌ Sustainability features
- ❌ German/English language toggle (English-only in v0; UI is short enough that this isn't a barrier)
- ❌ App Store / TestFlight publishing
- ❌ Auth / multi-user
- ❌ Onboarding tutorial

Anything in the above list that becomes urgent → re-brainstorm, re-scope, plan as v0.1 / v1.

---

## 16. Open architectural questions for implementation phase

These are intentionally left for the implementation plan (next step), not pre-decided here:

- Exact SwiftData schema migrations strategy
- Exact prompt token budget (we'll measure during implementation)
- Whether to use `URLSession` directly or a thin wrapper for Anthropic calls
- Specific Worker tech (plain TS vs. Hono framework)
- How to handle Anthropic streaming vs. one-shot for styling responses

---

**Next step:** User reviews this spec. On approval, transition to `superpowers:writing-plans` to produce an implementation plan.
