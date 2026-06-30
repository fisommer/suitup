import type { CrawlResponse } from "./types";
import { extractStructured } from "./extractors/structured";
import { extractWithVision } from "./extractors/vision";
import { extractVariantsFromURL } from "./extractors/variants";

const USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

const BROWSER_HEADERS: Record<string, string> = {
  "user-agent": USER_AGENT,
  accept:
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
  "accept-language": "en-US,en;q=0.9,de;q=0.8",
  "accept-encoding": "gzip, deflate, br",
  "cache-control": "no-cache",
  pragma: "no-cache",
};

const FETCH_TIMEOUT_MS = 10_000;

export async function timedFetch(
  url: string,
  init: RequestInit = {},
  ms: number = FETCH_TIMEOUT_MS
): Promise<Response> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal });
  } finally {
    clearTimeout(t);
  }
}

export async function crawl(url: string, anthropicKey: string): Promise<CrawlResponse> {
  const warnings: string[] = [];
  let html = "";

  try {
    const res = await timedFetch(url, { headers: BROWSER_HEADERS, redirect: "follow" });
    if (!res.ok) {
      return {
        success: false,
        images: [],
        data: {},
        warnings,
        error: `HTTP ${res.status}`,
      };
    }
    html = await res.text();
  } catch (e: any) {
    const msg = e?.name === "AbortError" ? "timeout (10s)" : `fetch failed: ${e.message ?? "unknown"}`;
    return {
      success: false,
      images: [],
      data: {},
      warnings,
      error: msg,
    };
  }

  const structured = extractStructured(html, url);
  const variants = extractVariantsFromURL(url);

  // Resolve variant codes via JSON-LD hasVariant if the structured pass produced a mapping.
  // Only surface `selectedColor`/`selectedSize` when we got a *readable* label — raw cryptic
  // codes like "COL00" are worse than the JSON-LD default color name, so suppress those.
  const resolvedColor = variants.color
    ? structured.variantLookup?.color?.[variants.color]
    : undefined;
  const resolvedSize = variants.size
    ? structured.variantLookup?.size?.[variants.size]
    : undefined;
  if (resolvedColor) structured.data.selectedColor = resolvedColor;
  if (resolvedSize) structured.data.selectedSize = resolvedSize;

  // When the URL has a color variant we couldn't resolve from the page's HTML, we have
  // a problem: the JSON-LD default color likely doesn't match the URL's selected color,
  // and the page's image set typically shows multiple variants (so vision-against-images
  // can pick the wrong one — e.g. a model shot in a different color than the swatch).
  //
  // Honest behaviour: clear the colors field and surface a warning, rather than auto-fill
  // a confidently-wrong value. The user picks the color manually on the confirm screen.
  const hasUnresolvedColor = !!variants.color && !resolvedColor;
  const hasUnresolvedSize = !!variants.size && !resolvedSize;
  if (hasUnresolvedColor) {
    structured.data.colors = undefined;
    structured.data.selectedColor = undefined;
    warnings.push(
      `URL has color variant "${variants.color}" but the page didn't expose a readable mapping. Please pick the color manually.`
    );
  }
  if (hasUnresolvedSize) {
    warnings.push(
      `URL has size variant "${variants.size}" but the page didn't expose a readable mapping. Please pick the size manually.`
    );
  }

  const haveEssentials = !!structured.data.name && structured.images.length > 0;

  if (haveEssentials) {
    if (!structured.data.price) warnings.push("price not detected");
    if (!structured.data.colors && !structured.data.selectedColor && !hasUnresolvedColor) {
      warnings.push("color not detected");
    }
    return {
      success: true,
      images: structured.images,
      data: structured.data,
      warnings,
    };
  }

  warnings.push("structured data insufficient — using vision fallback");
  if (!anthropicKey) {
    warnings.push("no anthropic key configured — vision fallback skipped");
    return {
      success: structured.images.length > 0 || !!structured.data.name,
      images: structured.images,
      data: structured.data,
      warnings,
    };
  }

  // Vision fallback path: only used when structured data was insufficient.
  // We don't pass URL variants here because if structured had no name, this isn't a
  // "reconcile color" situation — it's a "you have nothing at all" situation, and
  // letting vision report what it sees in the image is the best we can do.
  const vision = await extractWithVision(html, structured.images, url, anthropicKey);
  return {
    success: true,
    images: vision.images.length ? vision.images : structured.images,
    data: { ...structured.data, ...vision.data },
    warnings,
  };
}
