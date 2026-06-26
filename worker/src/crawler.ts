import type { CrawlResponse } from "./types";
import { extractStructured } from "./extractors/structured";
import { extractWithVision } from "./extractors/vision";

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

export async function crawl(url: string, anthropicKey: string): Promise<CrawlResponse> {
  const warnings: string[] = [];
  let html = "";

  try {
    const res = await fetch(url, { headers: BROWSER_HEADERS, redirect: "follow" });
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
    return {
      success: false,
      images: [],
      data: {},
      warnings,
      error: `fetch failed: ${e.message ?? "unknown"}`,
    };
  }

  const structured = extractStructured(html, url);
  const haveEssentials = !!structured.data.name && structured.images.length > 0;

  if (haveEssentials) {
    if (!structured.data.price) warnings.push("price not detected");
    if (!structured.data.colors) warnings.push("color not detected");
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

  const vision = await extractWithVision(html, structured.images, url, anthropicKey);
  return {
    success: true,
    images: vision.images.length ? vision.images : structured.images,
    data: { ...structured.data, ...vision.data },
    warnings,
  };
}
