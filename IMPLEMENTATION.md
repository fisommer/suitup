# SuitUp v0 — Implementation Plan

**Companion to:** `docs/specs/2026-06-26-suitup-v0-design.md`
**Date:** 2026-06-26
**Detail level:** Implementation steps with tests where they matter (not strict per-task TDD).
**Execution model:** Finn executes in Xcode + terminal. Phases are roughly sequential; phase boundaries are good commit/branch points.

## Phase overview

| # | Phase | Why it ships first | Rough size |
|---|---|---|---|
| 0 | Cloudflare Worker (URL crawler) | Independent, no iOS dependency, unblocks Flow 2 | Small (1-2 days) |
| 1 | Xcode project + SwiftData models + tab nav | Foundation for everything | Small (1 day) |
| 2 | Closet UI (Category Rails + item detail) | Visible progress, enables manual testing of model | Medium (2 days) |
| 3 | Flow 1 — Add item via photo (capture + bg-removal + auto-tag) | First end-to-end vertical slice | Medium (2-3 days) |
| 4 | Flow 2 — Add item via URL (uses Worker from Phase 0) | Reuses confirm-screen from Phase 3 | Small (1-2 days) |
| 5 | Flow 3 — Reference looks | Trivial after Flow 1 plumbing | Small (1 day) |
| 6 | Flow 4 — Style this piece + Flow 4b — Save outfit + collage renderer | The main event; biggest single phase | Large (3-5 days) |
| 7 | Flow 5 — Recreate this look + Wishlist | Reuses Flow 6 prompt patterns | Medium (2-3 days) |
| 8 | iOS Share Extension target | Polish + the killer integration | Medium (2 days) |
| 9 | Settings, polish, end-to-end verification | Definition-of-done pass | Small (1-2 days) |

Total order-of-magnitude: ~3-5 weeks of focused evenings/weekends. Not a timeline guarantee — just a sanity check.

## Conventions used in this plan

- File paths are relative to `~/Claude/suitup/` unless otherwise noted
- Code blocks are real Swift/TS, not pseudocode
- Where I say "commit", the suggested message uses Conventional Commits style
- Tests are XCTest for iOS, Vitest for the Worker
- Anywhere "TBD" appears, that's a real implementation detail to figure out when you get there (not a planning placeholder)

---

## Phase 0 — Cloudflare Worker (URL Crawler)

**Goal:** A deployed Worker at `https://suitup-crawler.<your-account>.workers.dev/crawl` that takes a product URL and returns structured product data. No iOS dependency.

### 0.1 — Scaffold the Worker project

```bash
cd ~/Claude/suitup
mkdir -p worker && cd worker
npm init -y
npm install --save-dev wrangler typescript @cloudflare/workers-types vitest @cloudflare/vitest-pool-workers
npm install hono cheerio
```

Create `worker/wrangler.toml`:

```toml
name = "suitup-crawler"
main = "src/index.ts"
compatibility_date = "2026-06-01"

[vars]
# non-secret defaults

# secrets set via `wrangler secret put ANTHROPIC_API_KEY`
```

Create `worker/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "esnext",
    "module": "esnext",
    "moduleResolution": "bundler",
    "lib": ["esnext"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "noEmit": true
  },
  "include": ["src/**/*.ts"]
}
```

**Commit:** `chore(worker): scaffold cloudflare worker project`

### 0.2 — Define the response type and routing

Create `worker/src/types.ts`:

```ts
export interface CrawlRequest {
  url: string;
}

export interface CrawlResponse {
  success: boolean;
  images: string[];
  data: {
    name?: string;
    brand?: string;
    price?: { value: number; currency: string };
    colors?: string[];
    materials?: string[];
    availableSizes?: string[];
    category?: string;
    description?: string;
  };
  warnings: string[];
  error?: string;
}
```

Create `worker/src/index.ts`:

```ts
import { Hono } from "hono";
import type { CrawlRequest, CrawlResponse } from "./types";
import { crawl } from "./crawler";

type Env = { ANTHROPIC_API_KEY: string };

const app = new Hono<{ Bindings: Env }>();

app.post("/crawl", async (c) => {
  let body: CrawlRequest;
  try {
    body = await c.req.json();
  } catch {
    return c.json<CrawlResponse>(
      { success: false, images: [], data: {}, warnings: [], error: "invalid JSON" },
      400
    );
  }
  if (!body.url || !/^https?:\/\//.test(body.url)) {
    return c.json<CrawlResponse>(
      { success: false, images: [], data: {}, warnings: [], error: "invalid url" },
      400
    );
  }
  const result = await crawl(body.url, c.env.ANTHROPIC_API_KEY);
  return c.json(result);
});

app.get("/health", (c) => c.text("ok"));

export default app;
```

**Commit:** `feat(worker): basic routing + crawl endpoint shape`

### 0.3 — Implement structured-data extraction (the cheap path)

Create `worker/src/extractors/structured.ts`:

```ts
import * as cheerio from "cheerio";
import type { CrawlResponse } from "../types";

export function extractStructured(html: string, baseUrl: string): Partial<CrawlResponse> {
  const $ = cheerio.load(html);
  const images = new Set<string>();
  const data: CrawlResponse["data"] = {};

  // 1. JSON-LD Product
  $('script[type="application/ld+json"]').each((_, el) => {
    try {
      const parsed = JSON.parse($(el).contents().text());
      const candidates = Array.isArray(parsed) ? parsed : [parsed];
      for (const c of candidates) {
        const products = unwrapProduct(c);
        for (const p of products) {
          if (p.name && !data.name) data.name = p.name;
          if (p.brand && !data.brand) {
            data.brand = typeof p.brand === "string" ? p.brand : p.brand.name;
          }
          if (p.image) {
            const imgs = Array.isArray(p.image) ? p.image : [p.image];
            imgs.forEach((i: string) => images.add(absolutize(i, baseUrl)));
          }
          if (p.offers) {
            const offer = Array.isArray(p.offers) ? p.offers[0] : p.offers;
            if (offer.price && offer.priceCurrency) {
              data.price = { value: Number(offer.price), currency: offer.priceCurrency };
            }
          }
          if (p.color && !data.colors) {
            data.colors = Array.isArray(p.color) ? p.color : [p.color];
          }
          if (p.material && !data.materials) {
            data.materials = Array.isArray(p.material) ? p.material : [p.material];
          }
          if (p.description && !data.description) data.description = p.description;
        }
      }
    } catch {
      // tolerate malformed JSON-LD
    }
  });

  // 2. OpenGraph fallbacks
  if (!data.name) data.name = $('meta[property="og:title"]').attr("content") || undefined;
  if (!data.description) data.description = $('meta[property="og:description"]').attr("content") || undefined;
  const ogImage = $('meta[property="og:image"]').attr("content");
  if (ogImage) images.add(absolutize(ogImage, baseUrl));

  // 3. Twitter card
  const twImage = $('meta[name="twitter:image"]').attr("content");
  if (twImage) images.add(absolutize(twImage, baseUrl));

  return { data, images: Array.from(images) };
}

function unwrapProduct(node: any): any[] {
  if (!node || typeof node !== "object") return [];
  if (node["@type"] === "Product") return [node];
  if (Array.isArray(node["@graph"])) {
    return node["@graph"].filter((n: any) => n["@type"] === "Product");
  }
  return [];
}

function absolutize(url: string, base: string): string {
  try {
    return new URL(url, base).toString();
  } catch {
    return url;
  }
}
```

**Test it.** Create `worker/test/structured.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { extractStructured } from "../src/extractors/structured";

const sampleJsonLd = `<html><head>
<script type="application/ld+json">{
  "@context":"https://schema.org",
  "@type":"Product",
  "name":"COS Linen Shirt",
  "brand":{"@type":"Brand","name":"COS"},
  "image":["https://example.com/shirt-1.jpg","https://example.com/shirt-2.jpg"],
  "offers":{"@type":"Offer","price":"69","priceCurrency":"EUR"},
  "color":"beige",
  "material":"100% linen"
}</script></head><body></body></html>`;

describe("extractStructured", () => {
  it("parses JSON-LD product", () => {
    const r = extractStructured(sampleJsonLd, "https://example.com/p/123");
    expect(r.data?.name).toBe("COS Linen Shirt");
    expect(r.data?.brand).toBe("COS");
    expect(r.data?.price).toEqual({ value: 69, currency: "EUR" });
    expect(r.data?.colors).toEqual(["beige"]);
    expect(r.images).toHaveLength(2);
  });

  it("falls back to OpenGraph when no JSON-LD", () => {
    const html = `<html><head>
      <meta property="og:title" content="Some Shirt" />
      <meta property="og:image" content="/img/shirt.jpg" />
    </head></html>`;
    const r = extractStructured(html, "https://shop.test/p/1");
    expect(r.data?.name).toBe("Some Shirt");
    expect(r.images?.[0]).toBe("https://shop.test/img/shirt.jpg");
  });
});
```

Run `npx vitest run` — expect green.

**Commit:** `feat(worker): structured-data extractor (JSON-LD + OpenGraph)`

### 0.4 — Implement the orchestrator (fetch + structured + AI fallback)

Create `worker/src/crawler.ts`:

```ts
import type { CrawlResponse } from "./types";
import { extractStructured } from "./extractors/structured";
import { extractWithVision } from "./extractors/vision";

const USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15 SuitUpBot/0.1";

export async function crawl(url: string, anthropicKey: string): Promise<CrawlResponse> {
  const warnings: string[] = [];
  let html = "";
  try {
    const res = await fetch(url, { headers: { "user-agent": USER_AGENT } });
    if (!res.ok) {
      return { success: false, images: [], data: {}, warnings, error: `HTTP ${res.status}` };
    }
    html = await res.text();
  } catch (e: any) {
    return { success: false, images: [], data: {}, warnings, error: `fetch failed: ${e.message}` };
  }

  const structured = extractStructured(html, url);
  const haveEssentials =
    !!structured.data?.name && (structured.images?.length ?? 0) > 0;

  if (haveEssentials) {
    if (!structured.data?.price) warnings.push("price not detected");
    if (!structured.data?.colors) warnings.push("color not detected");
    return {
      success: true,
      images: structured.images ?? [],
      data: structured.data ?? {},
      warnings,
    };
  }

  // Vision fallback
  warnings.push("structured data insufficient — using vision fallback");
  const vision = await extractWithVision(html, structured.images ?? [], url, anthropicKey);
  return {
    success: true,
    images: vision.images,
    data: { ...structured.data, ...vision.data },
    warnings,
  };
}
```

**Commit:** `feat(worker): crawler orchestrator (structured first, vision fallback)`

### 0.5 — Vision fallback

Create `worker/src/extractors/vision.ts`:

```ts
import * as cheerio from "cheerio";
import type { CrawlResponse } from "../types";

export async function extractWithVision(
  html: string,
  candidateImages: string[],
  pageUrl: string,
  apiKey: string
): Promise<{ data: CrawlResponse["data"]; images: string[] }> {
  const $ = cheerio.load(html);
  const title = $("title").text();
  const metaDesc = $('meta[name="description"]').attr("content") ?? "";
  const visibleText = $("body").text().replace(/\s+/g, " ").slice(0, 2000);

  // Pick top 3 candidate images by size hints
  const allImgs = candidateImages.length
    ? candidateImages
    : extractImageCandidates($, pageUrl);
  const topImages = allImgs.slice(0, 3);

  // If we have no images at all, give up
  if (topImages.length === 0) {
    return { data: { name: title || undefined, description: metaDesc || undefined }, images: [] };
  }

  // Fetch images as base64
  const imageBlocks = await Promise.all(
    topImages.map(async (url) => {
      try {
        const res = await fetch(url);
        if (!res.ok) return null;
        const buf = await res.arrayBuffer();
        const b64 = arrayBufferToBase64(buf);
        const contentType = res.headers.get("content-type") ?? "image/jpeg";
        return {
          type: "image" as const,
          source: { type: "base64" as const, media_type: contentType, data: b64 },
        };
      } catch {
        return null;
      }
    })
  );
  const validImageBlocks = imageBlocks.filter((b) => b !== null);

  const systemPrompt =
    "Extract clothing product details from the provided page content. Return null for any field you cannot determine confidently.";

  const toolDef = {
    name: "report_product",
    description: "Report the extracted clothing product data",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        brand: { type: "string" },
        category: { type: "string" },
        colors: { type: "array", items: { type: "string" } },
        materials: { type: "array", items: { type: "string" } },
        price: {
          type: "object",
          properties: {
            value: { type: "number" },
            currency: { type: "string" },
          },
        },
        availableSizes: { type: "array", items: { type: "string" } },
        description: { type: "string" },
      },
    },
  };

  const messages = [
    {
      role: "user",
      content: [
        ...validImageBlocks,
        {
          type: "text",
          text: `Page title: ${title}\nMeta description: ${metaDesc}\nVisible text: ${visibleText}`,
        },
      ],
    },
  ];

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-sonnet-latest",
      max_tokens: 1024,
      system: systemPrompt,
      tools: [toolDef],
      tool_choice: { type: "tool", name: "report_product" },
      messages,
    }),
  });

  if (!res.ok) {
    return {
      data: { name: title || undefined, description: metaDesc || undefined },
      images: topImages,
    };
  }
  const json = (await res.json()) as any;
  const toolUse = (json.content ?? []).find((c: any) => c.type === "tool_use");
  const extracted = toolUse?.input ?? {};
  return { data: extracted, images: topImages };
}

function extractImageCandidates($: cheerio.CheerioAPI, baseUrl: string): string[] {
  const imgs: string[] = [];
  $("img").each((_, el) => {
    const src = $(el).attr("src") || $(el).attr("data-src");
    if (!src) return;
    const width = parseInt($(el).attr("width") || "0", 10);
    const height = parseInt($(el).attr("height") || "0", 10);
    if (width > 0 && width < 200) return; // skip tiny
    if (height > 0 && height < 200) return;
    try {
      imgs.push(new URL(src, baseUrl).toString());
    } catch {
      /* skip */
    }
  });
  return imgs;
}

function arrayBufferToBase64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}
```

**Commit:** `feat(worker): vision fallback via Claude Sonnet`

### 0.6 — Deploy

```bash
cd worker
npx wrangler secret put ANTHROPIC_API_KEY     # paste your key
npx wrangler deploy
```

Test it from a terminal:

```bash
curl -X POST https://suitup-crawler.<your-account>.workers.dev/crawl \
  -H "content-type: application/json" \
  -d '{"url":"https://www.cos.com/en_eur/men/shirts/product.linen-shirt-beige.123.html"}'
```

Verify you get JSON with `success: true` and at least name + images.

Save the deployed URL — you'll plug it into the iOS app as `CRAWLER_BASE_URL`.

**Deployed URL (2026-06-26):** `https://suitup-crawler.yb4snpkzyn.workers.dev`

**Commit:** `chore(worker): deploy v0.1`

### Phase 0 acceptance

- `POST /crawl` returns valid JSON for Zalando, COS, Zara, ASOS, H&M product URLs
- Tests pass (`npx vitest run`)
- Deployed and accessible

---

## Phase 1 — Xcode Project + SwiftData Models + Tab Navigation

**Goal:** An app shell that launches, shows 4 tabs, has empty states, and persists SwiftData entities. No business logic yet.

### 1.1 — Create the Xcode project

In Xcode:
1. File → New → Project → iOS → App
2. Name: `SuitUp`
3. Interface: SwiftUI
4. Storage: SwiftData
5. Language: Swift
6. Save to `~/Claude/suitup/ios/`
7. Set minimum deployment to iOS 17.0

Verify the project builds and runs in Simulator (iPhone 15 Pro is fine).

**Commit:** `chore: scaffold xcode project (iOS 17, SwiftUI, SwiftData)`

### 1.2 — Define the SwiftData models

Create `ios/SuitUp/SuitUp/Models/Item.swift`:

```swift
import Foundation
import SwiftData

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case top, bottom, outerwear, footwear, accessory, fullBody
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .outerwear: return "Outerwear"
        case .footwear: return "Footwear"
        case .accessory: return "Accessory"
        case .fullBody: return "Full body"
        }
    }
}

enum Formality: String, Codable, CaseIterable {
    case casual, smartCasual, formal, sportswear
}

enum Season: String, Codable, CaseIterable {
    case spring, summer, autumn, winter
}

enum Fit: String, Codable, CaseIterable {
    case loose, regular, slim, tailored
}

enum ItemSource: String, Codable {
    case photo, urlCrawl
}

@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var imagePath: String
    var originalImagePath: String
    var thumbnailPath: String
    var additionalImagePaths: [String]
    var sourceRaw: String
    var sourceUrl: String?
    var name: String
    var categoryRaw: String
    var subcategory: String
    var colors: [String]
    var formalityRaw: String
    var seasonsRaw: [String]
    var pattern: String?
    var material: String?
    var brand: String?
    var size: String?
    var fitRaw: String?
    var occasionTags: [String]
    var purchaseDate: Date?
    var price: Decimal?
    var purchasedFrom: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        imagePath: String,
        originalImagePath: String,
        thumbnailPath: String,
        additionalImagePaths: [String] = [],
        source: ItemSource,
        sourceUrl: String? = nil,
        name: String,
        category: ItemCategory,
        subcategory: String,
        colors: [String],
        formality: Formality,
        seasons: [Season],
        pattern: String? = nil,
        material: String? = nil,
        brand: String? = nil,
        size: String? = nil,
        fit: Fit? = nil,
        occasionTags: [String] = [],
        purchaseDate: Date? = nil,
        price: Decimal? = nil,
        purchasedFrom: String? = nil,
        notes: String? = nil
    ) {
        let now = Date()
        self.id = id
        self.imagePath = imagePath
        self.originalImagePath = originalImagePath
        self.thumbnailPath = thumbnailPath
        self.additionalImagePaths = additionalImagePaths
        self.sourceRaw = source.rawValue
        self.sourceUrl = sourceUrl
        self.name = name
        self.categoryRaw = category.rawValue
        self.subcategory = subcategory
        self.colors = colors
        self.formalityRaw = formality.rawValue
        self.seasonsRaw = seasons.map(\.rawValue)
        self.pattern = pattern
        self.material = material
        self.brand = brand
        self.size = size
        self.fitRaw = fit?.rawValue
        self.occasionTags = occasionTags
        self.purchaseDate = purchaseDate
        self.price = price
        self.purchasedFrom = purchasedFrom
        self.notes = notes
        self.createdAt = now
        self.updatedAt = now
    }

    var category: ItemCategory { ItemCategory(rawValue: categoryRaw) ?? .top }
    var formality: Formality { Formality(rawValue: formalityRaw) ?? .casual }
    var seasons: [Season] { seasonsRaw.compactMap(Season.init(rawValue:)) }
    var source: ItemSource { ItemSource(rawValue: sourceRaw) ?? .photo }
    var fit: Fit? { fitRaw.flatMap(Fit.init(rawValue:)) }
}
```

Create `ios/SuitUp/SuitUp/Models/Outfit.swift`:

```swift
import Foundation
import SwiftData

enum OutfitSource: String, Codable {
    case manuallyBuilt, savedFromStyling
}

@Model
final class Outfit {
    @Attribute(.unique) var id: UUID
    var name: String
    var itemIds: [UUID]
    var coverImagePath: String
    var sourceRaw: String
    var rationale: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        itemIds: [UUID],
        coverImagePath: String,
        source: OutfitSource,
        rationale: String? = nil,
        notes: String? = nil
    ) {
        let now = Date()
        self.id = id
        self.name = name
        self.itemIds = itemIds
        self.coverImagePath = coverImagePath
        self.sourceRaw = source.rawValue
        self.rationale = rationale
        self.notes = notes
        self.createdAt = now
        self.updatedAt = now
    }

    var source: OutfitSource { OutfitSource(rawValue: sourceRaw) ?? .manuallyBuilt }
}
```

Create `ios/SuitUp/SuitUp/Models/ReferenceLook.swift`:

```swift
import Foundation
import SwiftData

enum ReferenceSource: String, Codable {
    case library, urlCrawl, shareSheet
}

@Model
final class ReferenceLook {
    @Attribute(.unique) var id: UUID
    var imagePath: String
    var thumbnailPath: String
    var sourceRaw: String
    var sourceUrl: String?
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        imagePath: String,
        thumbnailPath: String,
        source: ReferenceSource,
        sourceUrl: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
        self.sourceRaw = source.rawValue
        self.sourceUrl = sourceUrl
        self.note = note
        self.createdAt = Date()
    }

    var source: ReferenceSource { ReferenceSource(rawValue: sourceRaw) ?? .library }
}
```

Create `ios/SuitUp/SuitUp/Models/RecreateAttempt.swift`:

```swift
import Foundation
import SwiftData

enum MatchStatus: String, Codable { case matched, missing }
enum MatchConfidence: String, Codable { case veryClose, close, loose }

struct ParsedPiece: Codable, Hashable {
    let description: String
    let category: ItemCategory
    let colors: [String]
    let formality: Formality?
}

struct PieceMatch: Codable, Hashable {
    let pieceIndex: Int
    let status: MatchStatus
    let matchedItemId: UUID?
    let confidence: MatchConfidence?
    let note: String?
    var wantedPieceId: UUID?
}

@Model
final class RecreateAttempt {
    @Attribute(.unique) var id: UUID
    var sourceImagePath: String
    var sourceUrl: String?
    var parsedPiecesJSON: Data
    var matchesJSON: Data
    var recreatableCount: Int
    var totalPieceCount: Int
    var linkedReferenceLookId: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceImagePath: String,
        sourceUrl: String? = nil,
        parsedPieces: [ParsedPiece],
        matches: [PieceMatch],
        linkedReferenceLookId: UUID? = nil
    ) throws {
        self.id = id
        self.sourceImagePath = sourceImagePath
        self.sourceUrl = sourceUrl
        self.parsedPiecesJSON = try JSONEncoder().encode(parsedPieces)
        self.matchesJSON = try JSONEncoder().encode(matches)
        self.totalPieceCount = parsedPieces.count
        self.recreatableCount = matches.filter { $0.status == .matched }.count
        self.linkedReferenceLookId = linkedReferenceLookId
        self.createdAt = Date()
    }

    var parsedPieces: [ParsedPiece] {
        (try? JSONDecoder().decode([ParsedPiece].self, from: parsedPiecesJSON)) ?? []
    }
    var matches: [PieceMatch] {
        (try? JSONDecoder().decode([PieceMatch].self, from: matchesJSON)) ?? []
    }
}
```

Create `ios/SuitUp/SuitUp/Models/WantedPiece.swift`:

```swift
import Foundation
import SwiftData

@Model
final class WantedPiece {
    @Attribute(.unique) var id: UUID
    var pieceDescription: String
    var categoryRaw: String
    var colors: [String]
    var sourceRecreateAttemptId: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        pieceDescription: String,
        category: ItemCategory,
        colors: [String],
        sourceRecreateAttemptId: UUID
    ) {
        self.id = id
        self.pieceDescription = pieceDescription
        self.categoryRaw = category.rawValue
        self.colors = colors
        self.sourceRecreateAttemptId = sourceRecreateAttemptId
        self.createdAt = Date()
    }

    var category: ItemCategory { ItemCategory(rawValue: categoryRaw) ?? .top }
}
```

Create `ios/SuitUp/SuitUp/Models/EventLogs.swift`:

```swift
import Foundation
import SwiftData

@Model
final class WearEvent {
    @Attribute(.unique) var id: UUID
    var itemId: UUID?
    var outfitId: UUID?
    var timestamp: Date

    init(id: UUID = UUID(), itemId: UUID? = nil, outfitId: UUID? = nil) {
        self.id = id
        self.itemId = itemId
        self.outfitId = outfitId
        self.timestamp = Date()
    }
}

@Model
final class StylingRequest {
    @Attribute(.unique) var id: UUID
    var itemId: UUID
    var contextOccasion: String?
    var contextWeather: String?
    var closetSnapshotIds: [UUID]
    var suggestionsJSON: Data
    var modelCostUSD: Double?
    var timestamp: Date

    init(
        id: UUID = UUID(),
        itemId: UUID,
        contextOccasion: String? = nil,
        contextWeather: String? = nil,
        closetSnapshotIds: [UUID],
        suggestionsJSON: Data,
        modelCostUSD: Double? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.contextOccasion = contextOccasion
        self.contextWeather = contextWeather
        self.closetSnapshotIds = closetSnapshotIds
        self.suggestionsJSON = suggestionsJSON
        self.modelCostUSD = modelCostUSD
        self.timestamp = Date()
    }
}
```

Build to verify everything compiles.

**Commit:** `feat(models): swiftdata schema for items, outfits, references, recreate, wishlist, event logs`

### 1.3 — Wire up the ModelContainer

Edit `ios/SuitUp/SuitUp/SuitUpApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct SuitUpApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Outfit.self,
            ReferenceLook.self,
            RecreateAttempt.self,
            WantedPiece.self,
            WearEvent.self,
            StylingRequest.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

**Commit:** `feat: model container with all entities`

### 1.4 — Tab navigation shell with empty states

Create `ios/SuitUp/SuitUp/Features/RootTabView.swift`:

```swift
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ClosetTabView()
                .tabItem { Label("Closet", systemImage: "hanger") }
            OutfitsTabView()
                .tabItem { Label("Outfits", systemImage: "square.stack") }
            ReferencesTabView()
                .tabItem { Label("References", systemImage: "sparkles") }
            RecreateTabView()
                .tabItem { Label("Recreate", systemImage: "wand.and.stars") }
        }
    }
}
```

Create stub views in `ios/SuitUp/SuitUp/Features/Closet/ClosetTabView.swift`:

```swift
import SwiftUI

struct ClosetTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Your closet is empty",
                systemImage: "hanger",
                description: Text("Tap + to add your first piece.")
            )
            .navigationTitle("Closet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {}) { Image(systemName: "gearshape") }
                }
            }
        }
    }
}
```

Repeat the same empty-state pattern for `OutfitsTabView`, `ReferencesTabView`, `RecreateTabView` in their own folders under `Features/`. The empty-state messages differ ("No saved outfits yet", "No references yet", "No recreate attempts yet") but the structure is identical.

Build and run. Verify 4 tabs appear, each shows its empty state, the gear and `+` buttons appear in the closet toolbar.

**Commit:** `feat: tab navigation shell with empty states`

### Phase 1 acceptance

- App launches in Simulator
- 4 tabs visible, each with appropriate empty state
- SwiftData container initializes without error
- Models compile and conform to Swift 6 concurrency rules (no warnings)

---

(Continuing in next chunks. Phases 2–9 follow with the same level of code-included detail.)

## Phase 2 — Closet UI (Category Rails + Item Detail)

**Goal:** Browse items grouped by category in horizontal rails. Tap an item → detail screen. Items don't exist yet (will be created in Phase 3), so test with seeded fixtures.

### 2.1 — Image storage helper

Create `ios/SuitUp/SuitUp/Services/ImageStore.swift`:

```swift
import Foundation
import UIKit

enum ImageStoreFolder: String {
    case items, references, outfits, recreate
}

struct ImageStore {
    static func documentsDir() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static func folderURL(_ folder: ImageStoreFolder) -> URL {
        let url = documentsDir().appendingPathComponent(folder.rawValue)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Save a UIImage as JPEG. Returns the relative path (from documents dir).
    static func save(
        _ image: UIImage,
        folder: ImageStoreFolder,
        name: String,
        quality: CGFloat = 0.85,
        maxDimension: CGFloat? = nil
    ) throws -> String {
        let resized = maxDimension.map { resize(image, maxDimension: $0) } ?? image
        guard let data = resized.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "ImageStore", code: 1)
        }
        let url = folderURL(folder).appendingPathComponent("\(name).jpg")
        try data.write(to: url, options: .atomic)
        return "\(folder.rawValue)/\(name).jpg"
    }

    static func load(_ relativePath: String) -> UIImage? {
        let url = documentsDir().appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: url.path)
    }

    static func delete(_ relativePath: String) {
        let url = documentsDir().appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
```

**Commit:** `feat(services): ImageStore for local file persistence`

### 2.2 — A tiny image view that loads from disk

Create `ios/SuitUp/SuitUp/Features/Closet/Components/StoredImage.swift`:

```swift
import SwiftUI

struct StoredImage: View {
    let relativePath: String
    var contentMode: ContentMode = .fit

    var body: some View {
        if let img = ImageStore.load(relativePath) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Color.gray.opacity(0.15)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}
```

### 2.3 — Category Rails

Create `ios/SuitUp/SuitUp/Features/Closet/ClosetTabView.swift` (replacing the Phase 1 stub):

```swift
import SwiftUI
import SwiftData

struct ClosetTabView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var showingAddSheet = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Your closet is empty",
                        systemImage: "hanger",
                        description: Text("Tap + to add your first piece.")
                    )
                } else {
                    ClosetRailsView(items: items)
                }
            }
            .navigationTitle("Closet")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddItemSourceSheet()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}
```

Create `ios/SuitUp/SuitUp/Features/Closet/ClosetRailsView.swift`:

```swift
import SwiftUI

struct ClosetRailsView: View {
    let items: [Item]

    private var grouped: [(ItemCategory, [Item])] {
        let categoryOrder: [ItemCategory] = [.outerwear, .top, .bottom, .footwear, .accessory, .fullBody]
        return categoryOrder.compactMap { cat in
            let group = items.filter { $0.category == cat }
            return group.isEmpty ? nil : (cat, group)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(grouped, id: \.0) { (category, items) in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.displayName)
                            .font(.headline)
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(items) { item in
                                    NavigationLink(value: item) {
                                        RailItemTile(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
        }
    }
}

struct RailItemTile: View {
    let item: Item
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StoredImage(relativePath: item.thumbnailPath, contentMode: .fit)
                .frame(width: 110, height: 140)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)
        }
    }
}
```

### 2.4 — Item Detail screen (placeholder for now)

Create `ios/SuitUp/SuitUp/Features/Closet/ItemDetailView.swift`:

```swift
import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StoredImage(relativePath: item.imagePath, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .background(Color(.secondarySystemBackground))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.title2.bold())
                    Text("\(item.subcategory) · \(item.formality.rawValue)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Style this piece CTA (wired up in Phase 6)
                Button {
                    // TODO Phase 6
                } label: {
                    Label("Style this piece", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                DetailRow(label: "Category", value: item.category.displayName)
                if !item.colors.isEmpty {
                    DetailRow(label: "Colors", value: item.colors.joined(separator: ", "))
                }
                if !item.seasons.isEmpty {
                    DetailRow(label: "Seasons", value: item.seasons.map(\.rawValue).joined(separator: ", "))
                }
                if let brand = item.brand { DetailRow(label: "Brand", value: brand) }
                if let size = item.size { DetailRow(label: "Size", value: size) }
                if let material = item.material { DetailRow(label: "Material", value: material) }
                if let notes = item.notes, !notes.isEmpty {
                    DetailRow(label: "Notes", value: notes)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button(role: .destructive) { showingDeleteConfirm = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .confirmationDialog("Delete this item?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                ImageStore.delete(item.imagePath)
                ImageStore.delete(item.thumbnailPath)
                ImageStore.delete(item.originalImagePath)
                item.additionalImagePaths.forEach { ImageStore.delete($0) }
                modelContext.delete(item)
                dismiss()
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
        }
        .padding(.horizontal)
    }
}
```

### 2.5 — Stub add-item sheet & settings

Create `ios/SuitUp/SuitUp/Features/Closet/AddItemSourceSheet.swift`:

```swift
import SwiftUI

struct AddItemSourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button(action: {}) {
                    Label("Take photo", systemImage: "camera")
                }
                Button(action: {}) {
                    Label("Pick from library", systemImage: "photo")
                }
                Button(action: {}) {
                    Label("Paste link", systemImage: "link")
                }
            }
            .navigationTitle("Add to closet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

Create `ios/SuitUp/SuitUp/Features/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic API key") {
                    Text("To be wired up in Phase 9.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

### 2.6 — Seed data for manual testing

Create `ios/SuitUp/SuitUp/DevSupport/SeedData.swift` (only included in Debug builds — surround with `#if DEBUG`):

```swift
#if DEBUG
import SwiftData
import UIKit

enum SeedData {
    /// Call from the app once during development to populate a few fake items.
    /// Images: any JPEGs you drop into the Documents/items folder beforehand.
    static func seed(modelContext: ModelContext) {
        // Only seed if empty
        let descriptor = FetchDescriptor<Item>()
        if (try? modelContext.fetch(descriptor))?.isEmpty == false { return }

        let fakeImg = makePlaceholderImage()
        let path = (try? ImageStore.save(fakeImg, folder: .items, name: "seed-\(UUID())")) ?? ""

        let item = Item(
            imagePath: path,
            originalImagePath: path,
            thumbnailPath: path,
            source: .photo,
            name: "Seed Linen Shirt",
            category: .top,
            subcategory: "Shirt",
            colors: ["beige"],
            formality: .smartCasual,
            seasons: [.spring, .summer]
        )
        modelContext.insert(item)
    }

    private static func makePlaceholderImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 500))
        return renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 500))
        }
    }
}
#endif
```

You can call `SeedData.seed(modelContext: ...)` from `SuitUpApp` inside `onAppear` of `RootTabView` during dev only.

Build, run, verify rails appear when seeded.

**Commit:** `feat(closet): category rails + item detail + add-item sheet stubs`

### Phase 2 acceptance

- Empty state visible when closet is empty
- Seeded items appear in correct category rails
- Tap → ItemDetailView opens
- Delete from detail removes from closet
- `+` opens the add-item sheet stub
- Gear icon opens Settings stub

---

## Phase 3 — Flow 1: Add Item via Photo

**Goal:** End-to-end: take photo OR pick from library → background removal → auto-tag via Claude → confirm screen → save Item.

### 3.1 — Keychain helper for the Anthropic API key

Create `ios/SuitUp/SuitUp/Services/KeychainStore.swift`:

```swift
import Foundation
import Security

enum KeychainStore {
    private static let service = "dev.suitup.anthropic"
    private static let account = "api-key"

    static func set(_ value: String) {
        delete()
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &item)
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

Update `SettingsView` to read/write the key. Replace the Section body:

```swift
@State private var keyDraft = ""
@State private var keyExists = false

Section("Anthropic API key") {
    if keyExists {
        Text("Key stored")
        Button("Replace key", role: .none) {
            keyDraft = ""
        }
        Button("Delete key", role: .destructive) {
            KeychainStore.delete()
            keyExists = false
        }
    }
    SecureField("sk-ant-...", text: $keyDraft)
    Button("Save") {
        guard !keyDraft.isEmpty else { return }
        KeychainStore.set(keyDraft)
        keyDraft = ""
        keyExists = true
    }
}
.onAppear { keyExists = KeychainStore.get() != nil }
```

**Commit:** `feat(settings): anthropic api key in keychain`

### 3.2 — Background removal via iOS Vision

Create `ios/SuitUp/SuitUp/Services/BackgroundRemoval.swift`:

```swift
import UIKit
import Vision
import CoreImage

enum BackgroundRemoval {
    /// Returns a UIImage with the foreground subject isolated on transparent background.
    /// Falls back to the original if Vision can't find a subject.
    static func removeBackground(from image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return image }
            let maskBuffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
            let ciImage = CIImage(cvPixelBuffer: maskBuffer)
            let context = CIContext()
            guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else {
                return image
            }
            return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        } catch {
            return image
        }
    }
}
```

### 3.3 — Anthropic client

Create `ios/SuitUp/SuitUp/Services/AnthropicClient.swift`:

```swift
import Foundation
import UIKit

enum AnthropicError: Error, LocalizedError {
    case missingKey
    case httpError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Anthropic API key not configured."
        case .httpError(let code, let body): "HTTP \(code): \(body)"
        case .parseError(let s): "Parse error: \(s)"
        }
    }
}

struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let input_schema: [String: AnyEncodable]
}

struct AnyEncodable: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let b as Bool: try container.encode(b)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let arr as [Any]: try container.encode(arr.map(AnyEncodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyEncodable.init))
        case _ as NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }
}

struct AnthropicClient {
    enum ContentBlock {
        case text(String)
        case image(UIImage)
    }

    let model: String = "claude-sonnet-latest"
    let maxTokens: Int = 2048

    /// Make a tool-use call. Returns the tool input as a [String: Any] dictionary.
    func callTool(
        system: String,
        tool: AnthropicTool,
        userBlocks: [ContentBlock]
    ) async throws -> [String: Any] {
        guard let apiKey = KeychainStore.get(), !apiKey.isEmpty else {
            throw AnthropicError.missingKey
        }

        let contentJSON: [[String: Any]] = userBlocks.map { block in
            switch block {
            case .text(let s):
                return ["type": "text", "text": s]
            case .image(let img):
                let data = img.jpegData(compressionQuality: 0.85) ?? Data()
                let b64 = data.base64EncodedString()
                return [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": b64,
                    ]
                ]
            }
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "tools": [[
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.input_schema.mapValues { $0.value },
            ]],
            "tool_choice": ["type": "tool", "name": tool.name],
            "messages": [["role": "user", "content": contentJSON]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.parseError("no http response")
        }
        if http.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw AnthropicError.httpError(http.statusCode, bodyStr)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let toolUse = content.first(where: { ($0["type"] as? String) == "tool_use" }),
            let input = toolUse["input"] as? [String: Any]
        else {
            throw AnthropicError.parseError("no tool_use in response")
        }
        return input
    }
}
```

**Commit:** `feat(services): anthropic client with tool-use`

### 3.4 — Auto-tag service

Create `ios/SuitUp/SuitUp/Services/AutoTagger.swift`:

```swift
import UIKit

struct AutoTagResult {
    let name: String
    let category: ItemCategory
    let subcategory: String
    let colors: [String]
    let formality: Formality
    let seasons: [Season]
    let pattern: String?
    let material: String?
    let fit: Fit?
    let occasionTags: [String]
    let isNotClothing: Bool
}

struct AutoTagger {
    let client = AnthropicClient()

    private let tool = AnthropicTool(
        name: "tag_item",
        description: "Report the identified clothing tags",
        input_schema: [
            "type": AnyEncodable("object"),
            "properties": AnyEncodable([
                "name": ["type": "string"],
                "category": ["type": "string", "enum": ItemCategory.allCases.map(\.rawValue) + ["not-clothing"]],
                "subcategory": ["type": "string"],
                "colors": ["type": "array", "items": ["type": "string"]],
                "formality": ["type": "string", "enum": Formality.allCases.map(\.rawValue)],
                "seasons": ["type": "array", "items": ["type": "string", "enum": Season.allCases.map(\.rawValue)]],
                "pattern": ["type": "string"],
                "material": ["type": "string"],
                "fit": ["type": "string", "enum": Fit.allCases.map(\.rawValue)],
                "occasionTags": ["type": "array", "items": ["type": "string"]],
            ]),
            "required": AnyEncodable(["name", "category"]),
        ]
    )

    private let system = """
    You are tagging a single clothing item from a photograph. Be precise. If the image is not a clothing item, set category="not-clothing". Mark material as your best guess. Leave fields you cannot determine confidently as omitted.
    """

    func tag(image: UIImage) async throws -> AutoTagResult {
        let input = try await client.callTool(
            system: system,
            tool: tool,
            userBlocks: [.image(image), .text("Identify and tag this clothing item.")]
        )

        let categoryStr = input["category"] as? String ?? "top"
        let isNotClothing = categoryStr == "not-clothing"
        let category = ItemCategory(rawValue: categoryStr) ?? .top

        return AutoTagResult(
            name: input["name"] as? String ?? "Untitled",
            category: category,
            subcategory: input["subcategory"] as? String ?? "",
            colors: input["colors"] as? [String] ?? [],
            formality: Formality(rawValue: input["formality"] as? String ?? "casual") ?? .casual,
            seasons: (input["seasons"] as? [String] ?? []).compactMap(Season.init(rawValue:)),
            pattern: input["pattern"] as? String,
            material: input["material"] as? String,
            fit: (input["fit"] as? String).flatMap(Fit.init(rawValue:)),
            occasionTags: input["occasionTags"] as? [String] ?? [],
            isNotClothing: isNotClothing
        )
    }
}
```

**Commit:** `feat(services): auto-tagger via claude vision`

### 3.5 — Photo capture & library picker UI

Create `ios/SuitUp/SuitUp/Features/ItemCapture/ImagePicker.swift` (PhotosUI wrapper):

```swift
import SwiftUI
import PhotosUI

struct LibraryPicker: View {
    @Binding var selection: PhotosPickerItem?
    var body: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            Label("Pick from library", systemImage: "photo")
        }
    }
}
```

For camera capture, a simple UIImagePickerController wrapper:

```swift
import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }

    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let img = info[.originalImage] as? UIImage { parent.onPicked(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
```

### 3.6 — Confirm screen (shared between Flow 1 and Flow 2)

Create `ios/SuitUp/SuitUp/Features/ItemCapture/ItemConfirmView.swift`:

```swift
import SwiftUI
import SwiftData

struct ItemConfirmDraft {
    var originalImage: UIImage
    var bgRemovedImage: UIImage
    var useBackgroundRemoved: Bool = true
    var name: String = ""
    var category: ItemCategory = .top
    var subcategory: String = ""
    var colors: [String] = []
    var formality: Formality = .casual
    var seasons: [Season] = []
    var pattern: String = ""
    var material: String = ""
    var brand: String = ""
    var size: String = ""
    var fit: Fit? = nil
    var occasionTags: [String] = []
    var purchaseDate: Date? = nil
    var price: Decimal? = nil
    var purchasedFrom: String? = nil
    var notes: String = ""
    var source: ItemSource = .photo
    var sourceUrl: String? = nil
    var additionalImages: [UIImage] = []
}

struct ItemConfirmView: View {
    @State var draft: ItemConfirmDraft
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Image(uiImage: draft.useBackgroundRemoved ? draft.bgRemovedImage : draft.originalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 280)
                    .frame(maxWidth: .infinity)
                Toggle("Background removed", isOn: $draft.useBackgroundRemoved)
            }
            Section("Details") {
                TextField("Name", text: $draft.name)
                Picker("Category", selection: $draft.category) {
                    ForEach(ItemCategory.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Subcategory", text: $draft.subcategory)
                Picker("Formality", selection: $draft.formality) {
                    ForEach(Formality.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Colors (comma-separated)", text: Binding(
                    get: { draft.colors.joined(separator: ", ") },
                    set: { draft.colors = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                ))
            }
            Section("Optional") {
                TextField("Brand", text: $draft.brand)
                TextField("Size", text: $draft.size)
                TextField("Material", text: $draft.material)
                TextField("Notes", text: $draft.notes, axis: .vertical)
            }
            Section {
                Button("Save to closet") { save() }
                Button("Discard", role: .destructive) { dismiss() }
            }
        }
        .navigationTitle("Confirm")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        let baseImage = draft.useBackgroundRemoved ? draft.bgRemovedImage : draft.originalImage
        let id = UUID()
        do {
            let imagePath = try ImageStore.save(baseImage, folder: .items, name: "\(id)", maxDimension: 1024)
            let thumb = try ImageStore.save(baseImage, folder: .items, name: "\(id)-thumb", maxDimension: 256)
            let original = try ImageStore.save(draft.originalImage, folder: .items, name: "\(id)-original", maxDimension: 1600)
            let extraPaths: [String] = try draft.additionalImages.enumerated().map { idx, img in
                try ImageStore.save(img, folder: .items, name: "\(id)-extra-\(idx)", maxDimension: 1024)
            }
            let item = Item(
                id: id,
                imagePath: imagePath,
                originalImagePath: original,
                thumbnailPath: thumb,
                additionalImagePaths: extraPaths,
                source: draft.source,
                sourceUrl: draft.sourceUrl,
                name: draft.name.isEmpty ? "Untitled" : draft.name,
                category: draft.category,
                subcategory: draft.subcategory,
                colors: draft.colors,
                formality: draft.formality,
                seasons: draft.seasons,
                pattern: draft.pattern.isEmpty ? nil : draft.pattern,
                material: draft.material.isEmpty ? nil : draft.material,
                brand: draft.brand.isEmpty ? nil : draft.brand,
                size: draft.size.isEmpty ? nil : draft.size,
                fit: draft.fit,
                occasionTags: draft.occasionTags,
                purchaseDate: draft.purchaseDate,
                price: draft.price,
                purchasedFrom: draft.purchasedFrom,
                notes: draft.notes.isEmpty ? nil : draft.notes
            )
            modelContext.insert(item)
            try? modelContext.save()
            dismiss()
        } catch {
            print("Save failed: \(error)")
        }
    }
}
```

### 3.7 — Orchestrating Flow 1

Update `AddItemSourceSheet` to drive the flow:

```swift
struct AddItemSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var workingImage: UIImage?
    @State private var showAnalyzing = false
    @State private var draft: ItemConfirmDraft?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                LibraryPicker(selection: $libraryItem)
                Button { /* paste link — Phase 4 */ } label: { Label("Paste link", systemImage: "link") }
            }
            .navigationTitle("Add to closet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    Task { await beginProcessing(img) }
                }
            }
            .onChange(of: libraryItem) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await beginProcessing(img)
                    }
                }
            }
            .overlay { if showAnalyzing { AnalyzingOverlay() } }
            .alert("Tagging failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ), actions: { Button("OK", role: .cancel) {} }, message: { Text(errorMessage ?? "") })
            .sheet(item: Binding(
                get: { draft.map { DraftWrapper(draft: $0) } },
                set: { draft = $0?.draft }
            )) { wrapper in
                NavigationStack { ItemConfirmView(draft: wrapper.draft) }
            }
        }
    }

    @MainActor
    private func beginProcessing(_ image: UIImage) async {
        showAnalyzing = true
        let bgRemoved = await BackgroundRemoval.removeBackground(from: image)
        var d = ItemConfirmDraft(originalImage: image, bgRemovedImage: bgRemoved)
        do {
            let result = try await AutoTagger().tag(image: bgRemoved)
            d.name = result.name
            d.category = result.category
            d.subcategory = result.subcategory
            d.colors = result.colors
            d.formality = result.formality
            d.seasons = result.seasons
            d.material = result.material ?? ""
            d.fit = result.fit
            d.occasionTags = result.occasionTags
        } catch {
            errorMessage = error.localizedDescription
        }
        showAnalyzing = false
        draft = d
    }
}

private struct DraftWrapper: Identifiable {
    var id = UUID()
    var draft: ItemConfirmDraft
}

private struct AnalyzingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Analyzing…").foregroundStyle(.white)
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
```

### 3.8 — End-to-end manual test

1. Run the app on Simulator or device
2. Enter a valid Anthropic API key in Settings
3. Tap `+` → Pick from library → choose a photo of a clothing item
4. Wait for "Analyzing…" — should resolve in ~5-10s
5. Confirm screen appears with pre-filled tags
6. Tap "Save to closet"
7. Closet rail shows the item

**Commit:** `feat(flow1): add-via-photo end-to-end (bg-removal + auto-tag + confirm)`

### Phase 3 acceptance

- Camera and library both work
- Background removal produces a transparent-ish image (no white halo on iOS 17+)
- Auto-tag returns reasonable values for ~80% of clothing photos
- Manual edits in confirm screen persist correctly
- Saved item shows in the correct category rail

---

(Phases 4-9 follow next.)

## Phase 4 — Flow 2: Add Item via URL

**Goal:** Paste a product URL → app calls the Worker → preview images → confirm screen prefilled.

### 4.1 — Set the Worker URL constant

Create `ios/SuitUp/SuitUp/Services/AppConfig.swift`:

```swift
import Foundation

enum AppConfig {
    /// Replace with your deployed Worker URL after Phase 0.
    static let crawlerBaseURL = URL(string: "https://suitup-crawler.<your-account>.workers.dev")!
}
```

### 4.2 — Crawler client

Create `ios/SuitUp/SuitUp/Services/CrawlerClient.swift`:

```swift
import Foundation
import UIKit

struct CrawlResult: Decodable {
    struct DataBlock: Decodable {
        let name: String?
        let brand: String?
        let category: String?
        let colors: [String]?
        let materials: [String]?
        let price: Price?
        let availableSizes: [String]?
        let description: String?
        struct Price: Decodable {
            let value: Double
            let currency: String
        }
    }
    let success: Bool
    let images: [String]
    let data: DataBlock
    let warnings: [String]
    let error: String?
}

enum CrawlerError: Error, LocalizedError {
    case http(Int, String)
    case decoding(String)
    case noImages
    var errorDescription: String? {
        switch self {
        case .http(let c, let b): "HTTP \(c): \(b)"
        case .decoding(let s): "Decoding: \(s)"
        case .noImages: "No product images found at that URL."
        }
    }
}

struct CrawlerClient {
    func crawl(url: String) async throws -> CrawlResult {
        var req = URLRequest(url: AppConfig.crawlerBaseURL.appendingPathComponent("crawl"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(["url": url])

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        if let http, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CrawlerError.http(http.statusCode, body)
        }
        do {
            return try JSONDecoder().decode(CrawlResult.self, from: data)
        } catch {
            throw CrawlerError.decoding(error.localizedDescription)
        }
    }

    /// Download an image URL into a UIImage.
    func downloadImage(_ urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw CrawlerError.decoding("invalid url")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let img = UIImage(data: data) else {
            throw CrawlerError.decoding("not an image")
        }
        return img
    }
}
```

### 4.3 — Paste-URL flow UI

Create `ios/SuitUp/SuitUp/Features/ItemCapture/PasteURLView.swift`:

```swift
import SwiftUI

struct PasteURLView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var phase: Phase = .input
    @State private var crawl: CrawlResult?
    @State private var images: [UIImage] = []
    @State private var selectedIndex: Int = 0
    @State private var errorMessage: String?

    enum Phase { case input, crawling, picker, done }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input: inputView
                case .crawling: ProgressView("Fetching…").padding()
                case .picker: pickerView
                case .done: EmptyView()
                }
            }
            .navigationTitle("Add from link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Crawl failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ), actions: { Button("OK", role: .cancel) {} }, message: { Text(errorMessage ?? "") })
        }
    }

    private var inputView: some View {
        Form {
            Section("Product URL") {
                TextField("https://…", text: $urlText)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if let clip = UIPasteboard.general.string,
                   clip.lowercased().hasPrefix("http") {
                    Button("Paste \"\(clip.prefix(40))…\"") { urlText = clip }
                }
            }
            Section { Button("Continue") { Task { await beginCrawl() } }.disabled(urlText.isEmpty) }
        }
    }

    private var pickerView: some View {
        VStack(spacing: 16) {
            Text("Pick the best photo").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(images.enumerated()), id: \.offset) { idx, img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 260)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(idx == selectedIndex ? Color.accentColor : .clear, lineWidth: 3)
                            )
                            .onTapGesture { selectedIndex = idx }
                    }
                }
                .padding(.horizontal)
            }
            Button("Use selected") { Task { await proceedToConfirm() } }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    @MainActor
    private func beginCrawl() async {
        phase = .crawling
        do {
            let result = try await CrawlerClient().crawl(url: urlText)
            guard !result.images.isEmpty else { throw CrawlerError.noImages }
            crawl = result
            let downloaded = try await withThrowingTaskGroup(of: (Int, UIImage).self) { group in
                for (idx, urlStr) in result.images.prefix(6).enumerated() {
                    group.addTask { (idx, try await CrawlerClient().downloadImage(urlStr)) }
                }
                var collected: [(Int, UIImage)] = []
                for try await pair in group { collected.append(pair) }
                return collected.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
            }
            images = downloaded
            phase = images.count > 1 ? .picker : .crawling
            if images.count == 1 { await proceedToConfirm() }
        } catch {
            errorMessage = error.localizedDescription
            phase = .input
        }
    }

    @MainActor
    private func proceedToConfirm() async {
        guard let crawl, !images.isEmpty else { return }
        let chosen = images[selectedIndex]
        let bgRemoved = await BackgroundRemoval.removeBackground(from: chosen)
        var draft = ItemConfirmDraft(originalImage: chosen, bgRemovedImage: bgRemoved)
        draft.source = .urlCrawl
        draft.sourceUrl = urlText
        draft.name = crawl.data.name ?? ""
        draft.brand = crawl.data.brand ?? ""
        draft.colors = crawl.data.colors ?? []
        draft.material = crawl.data.materials?.first ?? ""
        if let cat = crawl.data.category, let mapped = mapCategory(cat) { draft.category = mapped }
        draft.notes = crawl.data.description ?? ""
        if let domain = URL(string: urlText)?.host { draft.purchasedFrom = domain }
        if let p = crawl.data.price { draft.price = Decimal(p.value) }

        // present confirm
        dismiss()
        // The caller (Closet) should handle re-opening the confirm sheet with this draft.
        // For now we just push it via a notification or use a shared state holder — TBD wiring.
    }

    private func mapCategory(_ s: String) -> ItemCategory? {
        let lower = s.lowercased()
        if lower.contains("shoe") || lower.contains("sneaker") || lower.contains("boot") { return .footwear }
        if lower.contains("jacket") || lower.contains("coat") || lower.contains("hoodie") { return .outerwear }
        if lower.contains("pant") || lower.contains("trouser") || lower.contains("jean") || lower.contains("short") { return .bottom }
        if lower.contains("dress") || lower.contains("jumpsuit") { return .fullBody }
        if lower.contains("hat") || lower.contains("scarf") || lower.contains("belt") { return .accessory }
        return .top
    }
}
```

> **Wiring note:** The `proceedToConfirm` call needs to hand the draft back to `AddItemSourceSheet`. Simplest approach: replace the in-line confirm presentation with a shared `@StateObject DraftHolder` ObservableObject scoped to the sheet. Implement that when wiring up — the structure is the same as the photo flow.

Hook into `AddItemSourceSheet`:

```swift
// Inside AddItemSourceSheet's List:
Button { showPasteURL = true } label: { Label("Paste link", systemImage: "link") }

// Add state:
@State private var showPasteURL = false

// Add sheet:
.sheet(isPresented: $showPasteURL) { PasteURLView() }
```

**Commit:** `feat(flow2): add-via-url end-to-end (crawler + image picker + confirm)`

### Phase 4 acceptance

- Pasting a Zalando/COS/Zara product URL → crawl succeeds → image picker appears (if multiple images) → confirm screen prefilled with name, brand, price
- 404 / blocked URLs show a clean error
- Saved Item has `source = urlCrawl`, `sourceUrl` populated, `purchasedFrom = domain`

---

## Phase 5 — Flow 3: References

**Goal:** Library/URL/share-sheet sources, all converging on a simple "preview + save" screen. No tags.

### 5.1 — References tab view

Replace stub with `ios/SuitUp/SuitUp/Features/References/ReferencesTabView.swift`:

```swift
import SwiftUI
import SwiftData

struct ReferencesTabView: View {
    @Query(sort: \ReferenceLook.createdAt, order: .reverse) private var refs: [ReferenceLook]
    @State private var showingAdd = false

    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if refs.isEmpty {
                    ContentUnavailableView(
                        "No references yet",
                        systemImage: "sparkles",
                        description: Text("Save 15-30 outfits you love to teach SuitUp your taste.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 4) {
                            ForEach(refs) { ref in
                                NavigationLink(value: ref) {
                                    StoredImage(relativePath: ref.thumbnailPath, contentMode: .fill)
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipped()
                                }
                            }
                        }
                    }
                    .navigationDestination(for: ReferenceLook.self) { ReferenceDetailView(ref: $0) }
                }
            }
            .navigationTitle("References")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) { AddReferenceSheet() }
        }
    }
}

struct ReferenceDetailView: View {
    @Bindable var ref: ReferenceLook
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                StoredImage(relativePath: ref.imagePath, contentMode: .fit)
                    .frame(maxHeight: 500)
                TextField("Note", text: Binding(get: { ref.note ?? "" }, set: { ref.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .padding()
                Button("Delete", role: .destructive) {
                    ImageStore.delete(ref.imagePath)
                    ImageStore.delete(ref.thumbnailPath)
                    modelContext.delete(ref)
                    dismiss()
                }
            }
        }
    }
}
```

### 5.2 — Add Reference sheet

Create `ios/SuitUp/SuitUp/Features/References/AddReferenceSheet.swift`:

```swift
import SwiftUI
import PhotosUI

struct AddReferenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var libItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    Section {
                        Image(uiImage: preview)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 320)
                        TextField("Optional note", text: $note)
                        Button("Add to references") { save(preview: preview) }
                    }
                } else {
                    Section { LibraryPicker(selection: $libItem) }
                }
            }
            .navigationTitle("Add reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: libItem) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        preview = img
                    }
                }
            }
        }
    }

    private func save(preview: UIImage) {
        let id = UUID()
        do {
            let path = try ImageStore.save(preview, folder: .references, name: "\(id)", maxDimension: 1024)
            let thumb = try ImageStore.save(preview, folder: .references, name: "\(id)-thumb", maxDimension: 256)
            let ref = ReferenceLook(
                id: id,
                imagePath: path,
                thumbnailPath: thumb,
                source: .library,
                note: note.isEmpty ? nil : note
            )
            modelContext.insert(ref)
            try? modelContext.save()
            dismiss()
        } catch {
            print("Save reference failed: \(error)")
        }
    }
}
```

**Commit:** `feat(flow3): references tab + add/edit/delete`

### Phase 5 acceptance

- Empty state visible with 0 references
- Adding a library image creates a `ReferenceLook` with thumbnail
- Tap → detail with editable note + delete
- Pinterest-style grid renders correctly with 10+ references

---

## Phase 6 — Flow 4 (Style this piece) + Flow 4b (Save outfit) + Collage Renderer

**Goal:** The main event. Tap an item → AI returns 3 outfits → user can save any as an Outfit. Manual outfit builder also available.

This phase is the largest. Subdivide into:
- 6.1 Collage renderer (used by both flows)
- 6.2 Styling service (Anthropic call + validation)
- 6.3 Styling UI (request → results → save)
- 6.4 Outfits tab + manual outfit builder
- 6.5 Wire "Style this piece" CTA from Item detail
- 6.6 Wear event logging

### 6.1 — Collage renderer

Create `ios/SuitUp/SuitUp/Services/CollageRenderer.swift`:

```swift
import UIKit
import SwiftUI

enum CollageRenderer {
    /// Produces a 4:5 portrait JPEG flat-lay collage from a set of items, ordered by category.
    @MainActor
    static func render(items: [Item], size: CGSize = CGSize(width: 800, height: 1000)) -> UIImage {
        let order: [ItemCategory] = [.outerwear, .top, .bottom, .footwear, .accessory, .fullBody]
        let sorted = items.sorted { lhs, rhs in
            (order.firstIndex(of: lhs.category) ?? 99) < (order.firstIndex(of: rhs.category) ?? 99)
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Simple vertical stack layout. Outerwear top-left, top top-right (if both),
            // otherwise centered. Bottom in middle. Footwear bottom-center. Accessories scattered.
            let positions = layoutPositions(for: sorted, in: size)
            for (item, rect) in zip(sorted, positions) {
                if let img = ImageStore.load(item.imagePath) {
                    let fitted = aspectFit(img.size, into: rect.size)
                    let origin = CGPoint(
                        x: rect.midX - fitted.width / 2,
                        y: rect.midY - fitted.height / 2
                    )
                    img.draw(in: CGRect(origin: origin, size: fitted))
                }
            }
        }
    }

    private static func layoutPositions(for items: [Item], in size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height
        switch items.count {
        case 1: return [CGRect(x: w * 0.1, y: h * 0.1, width: w * 0.8, height: h * 0.8)]
        case 2: return [
            CGRect(x: 0, y: 0, width: w, height: h * 0.5),
            CGRect(x: 0, y: h * 0.5, width: w, height: h * 0.5),
        ]
        case 3: return [
            CGRect(x: 0, y: 0, width: w, height: h * 0.4),
            CGRect(x: 0, y: h * 0.4, width: w, height: h * 0.4),
            CGRect(x: 0, y: h * 0.8, width: w, height: h * 0.2),
        ]
        default:
            let rowH = h / 2
            return items.enumerated().map { idx, _ in
                let col = idx % 2
                let row = idx / 2
                return CGRect(
                    x: CGFloat(col) * (w / 2),
                    y: CGFloat(row) * rowH,
                    width: w / 2,
                    height: rowH
                )
            }
        }
    }

    private static func aspectFit(_ source: CGSize, into target: CGSize) -> CGSize {
        let scale = min(target.width / source.width, target.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }
}
```

**Commit:** `feat(services): programmatic collage renderer`

### 6.2 — Styling service

Create `ios/SuitUp/SuitUp/Services/StylingService.swift`:

```swift
import Foundation
import UIKit

struct StyleSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let itemIds: [UUID]
    let rationale: String
}

enum StylingError: Error, LocalizedError {
    case noKey
    case noValidSuggestions
    case anthropic(Error)
    var errorDescription: String? {
        switch self {
        case .noKey: "Anthropic API key not set."
        case .noValidSuggestions: "Couldn't produce valid suggestions. Try again."
        case .anthropic(let e): e.localizedDescription
        }
    }
}

struct StylingService {
    let client = AnthropicClient()

    /// Returns up to 3 validated suggestions referencing real closet items.
    func suggestOutfits(
        for selected: Item,
        closet: [Item],
        savedOutfits: [Outfit],
        references: [ReferenceLook],
        previouslySuggested: [[UUID]] = []
    ) async throws -> [StyleSuggestion] {

        // Filter closet to compatible items (see spec §5 Flow 4)
        let compatible = filterCompatible(closet: closet, for: selected)

        // Limit by recency/relevance
        let cap = 30
        let closetSnapshot = Array(compatible.prefix(cap))
        let snapshotIds = Set(closetSnapshot.map(\.id))
        let savedWithSelected = savedOutfits.filter { $0.itemIds.contains(selected.id) }.prefix(5)
        let refsToSend = Array(references.prefix(10))

        var blocks: [AnthropicClient.ContentBlock] = []
        blocks.append(.text("SELECTED PIECE (must appear in every outfit):"))
        if let img = ImageStore.load(selected.imagePath) { blocks.append(.image(img)) }
        blocks.append(.text("ID: \(selected.id.uuidString)\nName: \(selected.name)\nCategory: \(selected.category.rawValue)\nColors: \(selected.colors.joined(separator: ","))\nFormality: \(selected.formality.rawValue)"))

        blocks.append(.text("\nREFERENCE LOOKS (the user's aesthetic — match this taste):"))
        for ref in refsToSend {
            if let img = ImageStore.load(ref.thumbnailPath) { blocks.append(.image(img)) }
        }

        blocks.append(.text("\nCLOSET INVENTORY (use ONLY these item IDs — never invent):"))
        for item in closetSnapshot {
            if let img = ImageStore.load(item.thumbnailPath) { blocks.append(.image(img)) }
            blocks.append(.text("ID: \(item.id.uuidString) — \(item.name) [\(item.category.rawValue), colors: \(item.colors.joined(separator: ","))]"))
        }

        if !savedWithSelected.isEmpty {
            blocks.append(.text("\nThe user has previously assembled these outfits with the selected piece (style anchor):"))
            for o in savedWithSelected {
                if let img = ImageStore.load(o.coverImagePath) { blocks.append(.image(img)) }
            }
        }

        if !previouslySuggested.isEmpty {
            blocks.append(.text("\nAVOID repeating these combinations:\n" + previouslySuggested.map { $0.map(\.uuidString).joined(separator: ",") }.joined(separator: "\n")))
        }

        let tool = AnthropicTool(
            name: "suggest_outfits",
            description: "Return 3 outfit suggestions",
            input_schema: [
                "type": AnyEncodable("object"),
                "properties": AnyEncodable([
                    "outfits": [
                        "type": "array",
                        "minItems": 3,
                        "maxItems": 3,
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": ["type": "string"],
                                "itemIds": ["type": "array", "items": ["type": "string"]],
                                "rationale": ["type": "string"],
                            ],
                            "required": ["name", "itemIds", "rationale"],
                        ],
                    ],
                ]),
                "required": AnyEncodable(["outfits"]),
            ]
        )

        let system = """
        You are a personal stylist. Suggest 3 outfits including the SELECTED PIECE.
        Use ONLY itemIds from the CLOSET INVENTORY — never invent items.
        Each outfit must include 3-5 items total (including the selected piece).
        Each outfit must be distinct.
        Lean toward the aesthetic of the reference looks.
        Provide a 1-2 sentence rationale per outfit.
        """

        let input: [String: Any]
        do {
            input = try await client.callTool(system: system, tool: tool, userBlocks: blocks)
        } catch {
            throw StylingError.anthropic(error)
        }

        guard let outfitsRaw = input["outfits"] as? [[String: Any]] else {
            throw StylingError.noValidSuggestions
        }

        var validSuggestions: [StyleSuggestion] = []
        for raw in outfitsRaw {
            guard
                let name = raw["name"] as? String,
                let idStrings = raw["itemIds"] as? [String],
                let rationale = raw["rationale"] as? String
            else { continue }
            let ids = idStrings.compactMap(UUID.init(uuidString:))
            // Validate: every id must be in the snapshot AND must include the selected
            let allValid = ids.allSatisfy { snapshotIds.contains($0) || $0 == selected.id }
            let includesSelected = ids.contains(selected.id)
            if allValid && includesSelected && ids.count >= 3 && ids.count <= 5 {
                validSuggestions.append(StyleSuggestion(name: name, itemIds: ids, rationale: rationale))
            }
        }

        guard validSuggestions.count >= 2 else { throw StylingError.noValidSuggestions }
        return validSuggestions
    }

    private func filterCompatible(closet: [Item], for selected: Item) -> [Item] {
        // Exclude items in the same primary slot as the selected piece (except outerwear, which can layer).
        let excludeCategory: ItemCategory? = {
            switch selected.category {
            case .top, .bottom, .footwear, .fullBody: return selected.category
            default: return nil
            }
        }()
        return closet.filter { item in
            if item.id == selected.id { return false }
            if let exclude = excludeCategory, item.category == exclude { return false }
            return true
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
```

**Commit:** `feat(services): styling service with closet-id validation`

### 6.3 — Styling UI

Create `ios/SuitUp/SuitUp/Features/Styling/StylingView.swift`:

```swift
import SwiftUI
import SwiftData

struct StylingView: View {
    let selected: Item
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var closet: [Item]
    @Query private var savedOutfits: [Outfit]
    @Query private var references: [ReferenceLook]

    @State private var phase: Phase = .generating
    @State private var suggestions: [StyleSuggestion] = []
    @State private var errorMessage: String?
    @State private var previouslySuggested: [[UUID]] = []

    enum Phase { case generating, results, error }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .generating: generatingView
                case .results: resultsView
                case .error: errorView
                }
            }
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if phase == .results {
                        Button { Task { await regenerate() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .task { await generate() }
        }
    }

    private var generatingView: some View {
        VStack(spacing: 16) {
            StoredImage(relativePath: selected.thumbnailPath).frame(width: 100, height: 130)
            ProgressView("Styling…")
            Text("Looking at your closet, references, and saved outfits").font(.caption).foregroundStyle(.secondary)
        }.padding()
    }

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let saved = savedOutfits.filter { $0.itemIds.contains(selected.id) }
                if !saved.isEmpty {
                    Text("You've worn this with").font(.headline).padding(.horizontal)
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(saved) { outfit in
                                NavigationLink(value: outfit) {
                                    StoredImage(relativePath: outfit.coverImagePath).frame(width: 110, height: 140).clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal)
                    }
                }
                Text("New ideas").font(.headline).padding(.horizontal)
                ForEach(suggestions) { suggestion in
                    SuggestionCard(suggestion: suggestion, allItems: closet) {
                        await saveAsOutfit(suggestion)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationDestination(for: Outfit.self) { OutfitDetailView(outfit: $0) }
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text(errorMessage ?? "Something went wrong").multilineTextAlignment(.center)
            Button("Try again") { Task { await generate() } }
        }.padding()
    }

    @MainActor
    private func generate() async {
        phase = .generating
        do {
            let result = try await StylingService().suggestOutfits(
                for: selected,
                closet: closet,
                savedOutfits: savedOutfits,
                references: references,
                previouslySuggested: previouslySuggested
            )
            suggestions = result
            phase = .results
        } catch {
            errorMessage = error.localizedDescription
            phase = .error
        }
    }

    @MainActor
    private func regenerate() async {
        previouslySuggested.append(contentsOf: suggestions.map { $0.itemIds })
        await generate()
    }

    @MainActor
    private func saveAsOutfit(_ suggestion: StyleSuggestion) async {
        let items = closet.filter { suggestion.itemIds.contains($0.id) }
        let collage = CollageRenderer.render(items: items)
        let id = UUID()
        do {
            let coverPath = try ImageStore.save(collage, folder: .outfits, name: "\(id)", maxDimension: 1024)
            let outfit = Outfit(
                id: id,
                name: suggestion.name,
                itemIds: suggestion.itemIds,
                coverImagePath: coverPath,
                source: .savedFromStyling,
                rationale: suggestion.rationale
            )
            modelContext.insert(outfit)
            try? modelContext.save()
        } catch {
            print("Save outfit failed: \(error)")
        }
    }
}

struct SuggestionCard: View {
    let suggestion: StyleSuggestion
    let allItems: [Item]
    let onSave: () async -> Void
    @State private var savedFlash = false

    private var items: [Item] {
        let map = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        return suggestion.itemIds.compactMap { map[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                CollageThumb(items: items).frame(width: 140, height: 175)
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.name).font(.headline)
                    Text(suggestion.rationale).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                ForEach(items) { item in
                    StoredImage(relativePath: item.thumbnailPath).frame(width: 50, height: 65).background(Color(.tertiarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Button { Task { await onSave(); savedFlash = true } } label: {
                Label(savedFlash ? "Saved" : "Save outfit", systemImage: "bookmark")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CollageThumb: View {
    let items: [Item]
    @State private var collage: UIImage?
    var body: some View {
        Group {
            if let collage {
                Image(uiImage: collage).resizable().aspectRatio(contentMode: .fit)
            } else {
                Color(.tertiarySystemBackground)
            }
        }
        .task { collage = CollageRenderer.render(items: items, size: CGSize(width: 280, height: 350)) }
    }
}
```

Wire "Style this piece" CTA in `ItemDetailView` (replace the TODO):

```swift
@State private var showingStyling = false

Button { showingStyling = true } label: {
    Label("Style this piece", systemImage: "sparkles")
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
}
.buttonStyle(.borderedProminent)
.padding(.horizontal)
.sheet(isPresented: $showingStyling) { StylingView(selected: item) }
```

### 6.4 — Outfits tab + manual builder + outfit detail

Create `ios/SuitUp/SuitUp/Features/Outfits/OutfitsTabView.swift`:

```swift
import SwiftUI
import SwiftData

struct OutfitsTabView: View {
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @State private var showingBuilder = false
    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if outfits.isEmpty {
                    ContentUnavailableView(
                        "No saved outfits yet",
                        systemImage: "square.stack",
                        description: Text("Save AI suggestions or build your own.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(outfits) { outfit in
                                NavigationLink(value: outfit) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        StoredImage(relativePath: outfit.coverImagePath).aspectRatio(4/5, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
                                        Text(outfit.name).font(.caption).lineLimit(1)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }.padding()
                    }
                    .navigationDestination(for: Outfit.self) { OutfitDetailView(outfit: $0) }
                }
            }
            .navigationTitle("Outfits")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingBuilder = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $showingBuilder) { OutfitBuilderView() }
        }
    }
}

struct OutfitDetailView: View {
    @Bindable var outfit: Outfit
    @Query private var allItems: [Item]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var items: [Item] {
        let map = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        return outfit.itemIds.compactMap { map[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StoredImage(relativePath: outfit.coverImagePath).aspectRatio(4/5, contentMode: .fit)
                TextField("Name", text: $outfit.name).font(.title2.bold()).padding(.horizontal)
                if let rationale = outfit.rationale {
                    Text(rationale).font(.body).foregroundStyle(.secondary).padding(.horizontal)
                }
                Text("Items").font(.headline).padding(.horizontal)
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        HStack {
                            StoredImage(relativePath: item.thumbnailPath).frame(width: 60, height: 75)
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text(item.subcategory).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                    }.buttonStyle(.plain)
                }
                Button("Wore today") {
                    modelContext.insert(WearEvent(outfitId: outfit.id))
                    try? modelContext.save()
                }.buttonStyle(.bordered).padding()
                Button("Delete outfit", role: .destructive) {
                    ImageStore.delete(outfit.coverImagePath)
                    modelContext.delete(outfit)
                    dismiss()
                }.padding()
            }
        }
        .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
    }
}

struct OutfitBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @State private var selectedIds: Set<UUID> = []
    @State private var name = "New outfit"

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $name) }
                Section("Pick 2-6 items") {
                    ForEach(allItems) { item in
                        Button { toggle(item.id) } label: {
                            HStack {
                                StoredImage(relativePath: item.thumbnailPath).frame(width: 40, height: 50)
                                Text(item.name)
                                Spacer()
                                if selectedIds.contains(item.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Section { Button("Save outfit") { save() }.disabled(selectedIds.count < 2 || selectedIds.count > 6) }
            }
            .navigationTitle("New outfit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }

    @MainActor
    private func save() {
        let items = allItems.filter { selectedIds.contains($0.id) }
        let collage = CollageRenderer.render(items: items)
        let id = UUID()
        do {
            let path = try ImageStore.save(collage, folder: .outfits, name: "\(id)", maxDimension: 1024)
            let outfit = Outfit(id: id, name: name, itemIds: Array(selectedIds), coverImagePath: path, source: .manuallyBuilt)
            modelContext.insert(outfit)
            try? modelContext.save()
            dismiss()
        } catch { print(error) }
    }
}
```

**Commit:** `feat(flow4): styling end-to-end with save-as-outfit, outfits tab, manual builder`

### Phase 6 acceptance

- Tap "Style this piece" on any item → 3 suggestions appear in ~10-15s
- All suggested itemIds correspond to actual closet items (validation works)
- "Save outfit" creates an Outfit with a programmatic collage cover
- Outfits tab shows saved outfits, tap → detail
- Manual builder produces a valid Outfit
- Refresh `↻` produces different suggestions

---


## Phase 7 — Flow 5: Recreate this Look + Wishlist

**Goal:** Paste/share/pick an outfit image → AI parses pieces and matches against closet → shows matched/missing → save matched-only outfit / wishlist missing pieces.

### 7.1 — Recreate service

Create `ios/SuitUp/SuitUp/Services/RecreateService.swift`:

```swift
import Foundation
import UIKit

struct RecreateResult {
    let parsedPieces: [ParsedPiece]
    let matches: [PieceMatch]
}

enum RecreateError: Error, LocalizedError {
    case noPieces
    case anthropic(Error)
    var errorDescription: String? {
        switch self {
        case .noPieces: "Couldn't identify any pieces in this image."
        case .anthropic(let e): e.localizedDescription
        }
    }
}

struct RecreateService {
    let client = AnthropicClient()

    func analyze(
        image: UIImage,
        closet: [Item],
        references: [ReferenceLook]
    ) async throws -> RecreateResult {

        let snapshotIds = Set(closet.map(\.id))

        var blocks: [AnthropicClient.ContentBlock] = []
        blocks.append(.text("REFERENCE OUTFIT (parse pieces and match against the closet):"))
        blocks.append(.image(image))

        blocks.append(.text("\nCLOSET INVENTORY (match against these — use only these item IDs):"))
        for item in closet {
            if let img = ImageStore.load(item.thumbnailPath) { blocks.append(.image(img)) }
            blocks.append(.text("ID: \(item.id.uuidString) — \(item.name) [\(item.category.rawValue), colors: \(item.colors.joined(separator: ","))]"))
        }
        if !references.isEmpty {
            blocks.append(.text("\nThe user's general taste anchor (for context only):"))
            for r in references.prefix(5) {
                if let img = ImageStore.load(r.thumbnailPath) { blocks.append(.image(img)) }
            }
        }

        let tool = AnthropicTool(
            name: "parse_and_match",
            description: "Parse the outfit and match each piece against the closet",
            input_schema: [
                "type": AnyEncodable("object"),
                "properties": AnyEncodable([
                    "parsedPieces": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "description": ["type": "string"],
                                "category": ["type": "string", "enum": ItemCategory.allCases.map(\.rawValue)],
                                "colors": ["type": "array", "items": ["type": "string"]],
                                "formality": ["type": "string", "enum": Formality.allCases.map(\.rawValue)],
                            ],
                            "required": ["description", "category", "colors"],
                        ],
                    ],
                    "matches": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "pieceIndex": ["type": "integer"],
                                "status": ["type": "string", "enum": ["matched", "missing"]],
                                "itemId": ["type": "string"],
                                "confidence": ["type": "string", "enum": ["veryClose", "close", "loose"]],
                                "note": ["type": "string"],
                            ],
                            "required": ["pieceIndex", "status"],
                        ],
                    ],
                ]),
                "required": AnyEncodable(["parsedPieces", "matches"]),
            ]
        )

        let system = """
        Parse the reference outfit into its primary pieces (top, bottom, outerwear, shoes, hero accessory — max 5).
        For each piece, either match to an itemId from the CLOSET INVENTORY or mark missing.
        Use ONLY itemIds from the inventory. Never invent.
        Match confidence: veryClose | close | loose.
        Include a short note explaining the match or what's missing.
        """

        let input: [String: Any]
        do {
            input = try await client.callTool(system: system, tool: tool, userBlocks: blocks)
        } catch {
            throw RecreateError.anthropic(error)
        }

        guard
            let piecesRaw = input["parsedPieces"] as? [[String: Any]],
            let matchesRaw = input["matches"] as? [[String: Any]]
        else { throw RecreateError.noPieces }

        let pieces: [ParsedPiece] = piecesRaw.compactMap { p in
            guard let desc = p["description"] as? String,
                  let catStr = p["category"] as? String,
                  let cat = ItemCategory(rawValue: catStr),
                  let colors = p["colors"] as? [String] else { return nil }
            let formality = (p["formality"] as? String).flatMap(Formality.init(rawValue:))
            return ParsedPiece(description: desc, category: cat, colors: colors, formality: formality)
        }
        guard !pieces.isEmpty else { throw RecreateError.noPieces }

        let matches: [PieceMatch] = matchesRaw.compactMap { m in
            guard let idx = m["pieceIndex"] as? Int,
                  let statusStr = m["status"] as? String,
                  let status = MatchStatus(rawValue: statusStr) else { return nil }
            var matchedId: UUID? = nil
            if status == .matched, let idStr = m["itemId"] as? String, let id = UUID(uuidString: idStr), snapshotIds.contains(id) {
                matchedId = id
            }
            // If it was supposed to be matched but invalid, downgrade to missing
            let effectiveStatus: MatchStatus = (status == .matched && matchedId == nil) ? .missing : status
            let confidence = (m["confidence"] as? String).flatMap(MatchConfidence.init(rawValue:))
            return PieceMatch(pieceIndex: idx, status: effectiveStatus, matchedItemId: matchedId, confidence: confidence, note: m["note"] as? String, wantedPieceId: nil)
        }

        return RecreateResult(parsedPieces: pieces, matches: matches)
    }
}
```

**Commit:** `feat(services): recreate service (parse + match in one call)`

### 7.2 — Recreate UI

Replace the stub `ios/SuitUp/SuitUp/Features/Recreate/RecreateTabView.swift`:

```swift
import SwiftUI
import SwiftData

struct RecreateTabView: View {
    @Query(sort: \RecreateAttempt.createdAt, order: .reverse) private var attempts: [RecreateAttempt]
    @Query(sort: \WantedPiece.createdAt, order: .reverse) private var wanted: [WantedPiece]
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showingAdd = true } label: { Label("New recreate", systemImage: "plus") }
                }
                if !wanted.isEmpty {
                    Section("Wishlist") {
                        ForEach(wanted) { w in
                            VStack(alignment: .leading) {
                                Text(w.pieceDescription)
                                Text("\(w.category.displayName) · \(w.colors.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("History") {
                    if attempts.isEmpty {
                        Text("No recreate attempts yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(attempts) { a in
                            NavigationLink(value: a) {
                                HStack {
                                    StoredImage(relativePath: a.sourceImagePath).frame(width: 60, height: 75)
                                    VStack(alignment: .leading) {
                                        Text("\(a.recreatableCount) of \(a.totalPieceCount) recreatable")
                                        Text(a.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recreate")
            .navigationDestination(for: RecreateAttempt.self) { RecreateResultView(attempt: $0) }
            .sheet(isPresented: $showingAdd) { NewRecreateSheet() }
        }
    }
}

struct NewRecreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var closet: [Item]
    @Query private var references: [ReferenceLook]
    @State private var libItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var phase: Phase = .input
    @State private var errorMessage: String?
    @State private var newAttempt: RecreateAttempt?

    enum Phase { case input, analyzing }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:
                    Form {
                        Section("Pick an outfit image") { LibraryPicker(selection: $libItem) }
                        if sourceImage != nil { Button("Analyze") { Task { await analyze() } } }
                    }
                case .analyzing:
                    VStack { ProgressView("Analyzing…").padding() }
                }
            }
            .navigationTitle("Recreate look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: libItem) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        sourceImage = img
                    }
                }
            }
            .alert("Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }), actions: { Button("OK", role: .cancel) {} }, message: { Text(errorMessage ?? "") })
        }
    }

    @MainActor
    private func analyze() async {
        guard let sourceImage else { return }
        phase = .analyzing
        do {
            let result = try await RecreateService().analyze(image: sourceImage, closet: closet, references: references)
            let id = UUID()
            let sourcePath = try ImageStore.save(sourceImage, folder: .recreate, name: "\(id)", maxDimension: 1024)
            let attempt = try RecreateAttempt(
                id: id,
                sourceImagePath: sourcePath,
                parsedPieces: result.parsedPieces,
                matches: result.matches
            )
            modelContext.insert(attempt)
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            phase = .input
        }
    }
}

struct RecreateResultView: View {
    @Bindable var attempt: RecreateAttempt
    @Query private var allItems: [Item]
    @Environment(\.modelContext) private var modelContext

    private var itemsById: [UUID: Item] {
        Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StoredImage(relativePath: attempt.sourceImagePath).frame(maxHeight: 400)
                Text("\(attempt.recreatableCount) of \(attempt.totalPieceCount) pieces recreatable")
                    .font(.headline)
                    .padding(.horizontal)
                ForEach(Array(attempt.matches.enumerated()), id: \.offset) { idx, match in
                    matchRow(match, piece: attempt.parsedPieces[safe: match.pieceIndex])
                        .padding(.horizontal)
                }
                Button("Save matched items as outfit") { saveMatchedOutfit() }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .disabled(attempt.recreatableCount == 0)
                Button("Save source image as reference") { saveAsReference() }
                    .padding(.horizontal)
            }
        }
        .navigationTitle("Recreate")
    }

    private func matchRow(_ match: PieceMatch, piece: ParsedPiece?) -> some View {
        HStack(alignment: .top) {
            Image(systemName: match.status == .matched ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(match.status == .matched ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(piece?.description ?? "Piece").font(.body)
                if match.status == .matched, let id = match.matchedItemId, let item = itemsById[id] {
                    NavigationLink(value: item) {
                        HStack {
                            StoredImage(relativePath: item.thumbnailPath).frame(width: 50, height: 65)
                            VStack(alignment: .leading) {
                                Text(item.name).font(.caption)
                                if let c = match.confidence { Text(c.rawValue).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } else if match.status == .missing {
                    HStack {
                        Text(match.note ?? "Missing from closet").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if match.wantedPieceId == nil {
                            Button("Save as want") { saveAsWant(match: match, piece: piece) }.font(.caption)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func saveAsWant(match: PieceMatch, piece: ParsedPiece?) {
        guard let piece else { return }
        let wanted = WantedPiece(
            pieceDescription: piece.description,
            category: piece.category,
            colors: piece.colors,
            sourceRecreateAttemptId: attempt.id
        )
        modelContext.insert(wanted)
        // Update the match record
        var updated = attempt.matches
        if let idx = updated.firstIndex(where: { $0.pieceIndex == match.pieceIndex }) {
            updated[idx].wantedPieceId = wanted.id
            attempt.matchesJSON = (try? JSONEncoder().encode(updated)) ?? attempt.matchesJSON
        }
        try? modelContext.save()
    }

    @MainActor
    private func saveMatchedOutfit() {
        let matchedIds = attempt.matches.compactMap { $0.matchedItemId }
        let items = matchedIds.compactMap { itemsById[$0] }
        guard !items.isEmpty else { return }
        let collage = CollageRenderer.render(items: items)
        let id = UUID()
        do {
            let path = try ImageStore.save(collage, folder: .outfits, name: "\(id)", maxDimension: 1024)
            let outfit = Outfit(
                id: id,
                name: "Recreated look",
                itemIds: matchedIds,
                coverImagePath: path,
                source: .manuallyBuilt,
                rationale: "From recreate attempt"
            )
            modelContext.insert(outfit)
            try? modelContext.save()
        } catch { print(error) }
    }

    private func saveAsReference() {
        let id = UUID()
        guard let img = ImageStore.load(attempt.sourceImagePath) else { return }
        do {
            let path = try ImageStore.save(img, folder: .references, name: "\(id)", maxDimension: 1024)
            let thumb = try ImageStore.save(img, folder: .references, name: "\(id)-thumb", maxDimension: 256)
            let ref = ReferenceLook(id: id, imagePath: path, thumbnailPath: thumb, source: .library)
            modelContext.insert(ref)
            attempt.linkedReferenceLookId = id
            try? modelContext.save()
        } catch { print(error) }
    }
}

extension Array {
    subscript(safe idx: Int) -> Element? { indices.contains(idx) ? self[idx] : nil }
}
```

**Commit:** `feat(flow5): recreate this look + wishlist`

### Phase 7 acceptance

- Pick a Pinterest outfit image → analyze → results show matched + missing pieces
- "Save as want" creates a WantedPiece, button disables after
- "Save matched items as outfit" creates an Outfit
- Wishlist visible in Recreate tab

---

## Phase 8 — iOS Share Extension Target

**Goal:** Tap share on a product page in Safari, IG, or Pinterest → SuitUp appears as a target → 1 tap saves it (to closet, reference, or recreate).

### 8.1 — Create the extension target

In Xcode:
1. File → New → Target → Share Extension
2. Name: `SuitUpShareExtension`
3. Embed in app

This generates `ShareViewController.swift` and `MainInterface.storyboard`.

### 8.2 — Set up the App Group

Both targets need access to a shared container so the extension can write payloads the main app reads.

1. Select the `SuitUp` target → Signing & Capabilities → `+ Capability` → App Groups → add `group.dev.suitup.shared`
2. Same for `SuitUpShareExtension`

Helper for the shared container:

```swift
// In a file shared between targets — e.g., add to both target memberships
import Foundation

enum SharedContainer {
    static let appGroupID = "group.dev.suitup.shared"

    static func url() -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)!
    }

    static func inboxURL() -> URL {
        let u = url().appendingPathComponent("inbox")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}
```

### 8.3 — Extension UI

Replace the generated `ShareViewController` with a SwiftUI-hosting controller:

```swift
import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let host = UIHostingController(rootView: ShareRouterView(
            inputItems: inputItems,
            onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            onCancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: NSError(domain: "user-cancel", code: 0)) }
        ))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }
}

enum SharePayloadKind { case image, url, mixed, unknown }

struct ShareRouterView: View {
    let inputItems: [NSExtensionItem]
    let onDone: () -> Void
    let onCancel: () -> Void
    @State private var kind: SharePayloadKind = .unknown
    @State private var pickedAction: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Add to SuitUp").font(.headline)
                if kind == .image || kind == .mixed {
                    Button("Save as reference") { route(action: "reference") }
                    Button("Recreate this look") { route(action: "recreate") }
                }
                if kind == .url || kind == .mixed {
                    Button("Add to closet (product link)") { route(action: "closet-url") }
                }
                if kind == .unknown {
                    Text("Detecting…")
                    ProgressView()
                }
                Button("Cancel", role: .cancel, action: onCancel).padding(.top, 8)
            }
            .padding()
            .task { await detectKind() }
        }
    }

    private func detectKind() async {
        var sawImage = false, sawURL = false
        for item in inputItems {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) { sawImage = true }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) { sawURL = true }
            }
        }
        kind = sawImage && sawURL ? .mixed : (sawImage ? .image : (sawURL ? .url : .unknown))
    }

    private func route(action: String) {
        Task {
            await writePayload(action: action)
            onDone()
        }
    }

    private func writePayload(action: String) async {
        var payload: [String: Any] = ["action": action, "timestamp": Date().timeIntervalSince1970]
        for item in inputItems {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let data = try? await loadImageData(provider) {
                        let id = UUID().uuidString
                        let dest = SharedContainer.inboxURL().appendingPathComponent("\(id).jpg")
                        try? data.write(to: dest)
                        payload["imagePath"] = "\(id).jpg"
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await loadURL(provider) {
                        payload["url"] = url.absoluteString
                    }
                }
            }
        }
        let manifestURL = SharedContainer.inboxURL().appendingPathComponent("\(UUID().uuidString).json")
        if let json = try? JSONSerialization.data(withJSONObject: payload) {
            try? json.write(to: manifestURL)
        }
    }

    private func loadImageData(_ provider: NSItemProvider) async throws -> Data? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: data)
            }
        }
    }
    private func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, err in
                if let err { cont.resume(throwing: err); return }
                if let url = item as? URL { cont.resume(returning: url) }
                else { cont.resume(returning: nil) }
            }
        }
    }
}
```

### 8.4 — Main app inbox pickup

In `SuitUpApp`, on launch and on `scenePhase` foreground transitions, scan the inbox:

```swift
import SwiftUI
import SwiftData

@main
struct SuitUpApp: App {
    // ... existing ModelContainer code ...
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingInbox: [InboxItem] = []

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modelContainer(sharedModelContainer)
                .task { await processInbox() }
                .onChange(of: scenePhase) { _, new in
                    if new == .active { Task { await processInbox() } }
                }
                .sheet(item: Binding(
                    get: { pendingInbox.first },
                    set: { _ in pendingInbox.removeFirst() }
                )) { inbox in
                    InboxRouterView(inbox: inbox)
                }
        }
    }

    @MainActor
    private func processInbox() async {
        let manifests = (try? FileManager.default.contentsOfDirectory(at: SharedContainer.inboxURL(), includingPropertiesForKeys: nil)) ?? []
        let jsonFiles = manifests.filter { $0.pathExtension == "json" }
        for url in jsonFiles {
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let item = InboxItem(
                    id: UUID(),
                    action: obj["action"] as? String ?? "",
                    imagePath: obj["imagePath"] as? String,
                    url: obj["url"] as? String
                )
                pendingInbox.append(item)
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

struct InboxItem: Identifiable {
    let id: UUID
    let action: String
    let imagePath: String?
    let url: String?
}

struct InboxRouterView: View {
    let inbox: InboxItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // Route to the appropriate flow:
            // - action="reference"     → ReferenceConfirmFromShare(image: …)
            // - action="recreate"      → NewRecreateSheet(preloadedImage: …)
            // - action="closet-url"    → PasteURLView(prefilledURL: …)
            // Implement these adapters when wiring this up.
            Text("Received: \(inbox.action)").padding()
            Button("Dismiss") { dismiss() }
        }
    }
}
```

> **Wiring note:** The three flow entry points (`AddReferenceSheet`, `NewRecreateSheet`, `PasteURLView`) already exist from earlier phases. Adapt each to accept a preloaded image/URL via initializer params. The InboxRouterView just picks one and presents it.

**Commit:** `feat: share extension target with inbox routing`

### Phase 8 acceptance

- Share an Instagram image to SuitUp → choose "Save as reference" → app launches → reference saved
- Share a Zalando product URL → choose "Add to closet" → URL crawl proceeds
- Share an image → choose "Recreate" → analysis kicks off

---

## Phase 9 — Settings, Polish, End-to-End Verification

**Goal:** Definition-of-Done pass against §13 of the spec.

### 9.1 — Settings polish

Add to `SettingsView`:

```swift
Section("Data") {
    Button("Export all data") { exportData() }
    Button("Clear all data", role: .destructive) { showClearConfirm = true }
}
Section("About") {
    LabeledContent("Version", value: Bundle.main.shortVersion)
    LabeledContent("Build", value: Bundle.main.buildNumber)
}
```

Helpers:

```swift
extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var buildNumber: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
}
```

Data export: JSON dump of all entities to a share sheet. Clear-all: confirmation dialog → wipe SwiftData + delete all files in Application Support / app group inbox.

### 9.2 — Empty-state polish

Each tab's empty state should now be tuned with helpful copy referencing what to do next (already mostly done in earlier phases — review and refine).

### 9.3 — Performance check

- Closet with 50+ items: ensure rails scroll at 60fps. If not, switch `StoredImage` to a small in-memory cache.
- Styling request: ensure progress text actually updates so it doesn't feel frozen.
- Image picker → bg removal → tagger: ensure the analyzing overlay doesn't block UI thread (everything's async; double-check `@MainActor` boundaries).

### 9.4 — DoD pass

Verify against §13 of the spec on your iPhone:

- [ ] Add ≥30 items via photo
- [ ] Add ≥5 items via URL crawl (from 2+ retailers)
- [ ] Add ≥15 reference looks
- [ ] Style 1+ closet item → 3 valid suggestions (no hallucinated items)
- [ ] Save ≥10 outfits (mix of manual + from-suggestion)
- [ ] Recreate ≥3 looks via share sheet
- [ ] Share Sheet works from Safari, Instagram, Pinterest

Anything that fails → small targeted fix, commit, retry.

### 9.5 — Final commit + tag

```bash
cd ~/Claude/suitup
git add -A
git commit -m "feat: v0 definition-of-done verified"
git tag v0.1.0
```

### Phase 9 acceptance

All 7 DoD checks pass on your iPhone.

---

## Appendix A — Running locally throughout development

- **Xcode build target:** iPhone 15 Pro (Simulator) for fast iteration; switch to your physical iPhone for camera-capture and share-sheet testing
- **Provisioning:** Free Apple Developer account works for device install; need to re-sign every 7 days unless you have a paid account
- **API key for dev:** Store in Keychain via Settings tab; never commit anywhere

## Appendix B — Worker secrets management

`wrangler secret put ANTHROPIC_API_KEY` once per environment. To rotate: same command. To remove: `wrangler secret delete ANTHROPIC_API_KEY`. Do not commit `.dev.vars` if you create one — add to `.gitignore`.

## Appendix C — Likely sources of cost/risk

| Risk | Mitigation |
|---|---|
| Anthropic costs balloon if you styling-spam during testing | Settings shows a running per-month tally (Phase 9 enhancement — optional) |
| Worker hits Cloudflare free-tier limit | Free tier = 100K requests/day. You will not hit this. |
| Image URLs in crawl results expire (CDN signed URLs) | Worker should always return permanent-feeling URLs; if not, download immediately and don't store the URL |
| iOS share-from-Instagram returns low-res images | Document workaround in Settings or in-app help; not blocking |
| SwiftData schema changes break upgrades | Use versioned migration plans the moment you ship a second build |

## Appendix D — Where this plan stops

This plan covers v0 only. After DoD pass, the roadmap items in `project_suitup_roadmap.md` (memory) become candidates for v0.1 / v1:

1. Travel/packing mode (HIGH priority)
2. AI-generated outfit collages (HIGH priority)
3. High-leverage buy recommendations (HIGH priority)
4. Daily context (weather, calendar)
5. Wear-tracking surfaces ("haven't worn in X days")
6. CloudKit sync
7. The rest of the Social Shopping Mirror vision

When picking the next thing to build, re-brainstorm — don't just grab from the list.

---

**Plan complete.** Open in Xcode, start with Phase 0 (the Worker), then Phase 1 (project setup). Each phase ends with a working build you can hand-test.
