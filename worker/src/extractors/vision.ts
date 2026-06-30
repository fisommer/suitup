import * as cheerio from "cheerio";
import type { CrawlResponse } from "../types";
import { timedFetch } from "../crawler";

interface VisionResult {
  data: CrawlResponse["data"];
  images: string[];
}

export async function extractWithVision(
  html: string,
  candidateImages: string[],
  pageUrl: string,
  apiKey: string,
  urlVariants?: { color?: string; size?: string }
): Promise<VisionResult> {
  const $ = cheerio.load(html);
  const title = $("title").text().trim();
  const metaDesc = ($('meta[name="description"]').attr("content") ?? "").trim();
  const visibleText = $("body").text().replace(/\s+/g, " ").trim().slice(0, 2000);

  const allImgs = candidateImages.length ? candidateImages : extractImageCandidates($, pageUrl);
  const topImages = allImgs.slice(0, 3);

  if (topImages.length === 0) {
    return {
      data: { name: title || undefined, description: metaDesc || undefined },
      images: [],
    };
  }

  const imageBlocks = await Promise.all(
    topImages.map(async (url) => {
      try {
        const res = await timedFetch(url, {}, 8_000);
        if (!res.ok) return null;
        const buf = await res.arrayBuffer();
        if (buf.byteLength === 0 || buf.byteLength > 4_500_000) return null;
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
  const validImageBlocks = imageBlocks.filter((b): b is NonNullable<typeof b> => b !== null);

  if (validImageBlocks.length === 0 && !title && !metaDesc) {
    return { data: {}, images: topImages };
  }

  const systemPrompt =
    "Extract clothing product details from the provided page content. Return null for any field you cannot determine confidently.";

  const variantHint = urlVariants?.color || urlVariants?.size
    ? `\n\nNote: the product URL has a variant selected via query params (${[
        urlVariants.color ? `color code "${urlVariants.color}"` : null,
        urlVariants.size ? `size code "${urlVariants.size}"` : null,
      ].filter(Boolean).join(", ")}). Look at the product images to determine the *actually-pictured* color — do NOT just report the page's generic default color. Report \`colors\` as what's visible in the images.`
    : "";

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
          text: `Page title: ${title}\nMeta description: ${metaDesc}\nVisible text: ${visibleText}${variantHint}`,
        },
      ],
    },
  ];

  try {
    const res = await timedFetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 1024,
        system: systemPrompt,
        tools: [toolDef],
        tool_choice: { type: "tool", name: "report_product" },
        messages,
      }),
    }, 15_000);

    if (!res.ok) {
      return {
        data: { name: title || undefined, description: metaDesc || undefined },
        images: topImages,
      };
    }
    const json = (await res.json()) as any;
    const toolUse = (json.content ?? []).find((c: any) => c.type === "tool_use");
    const extracted = (toolUse?.input ?? {}) as CrawlResponse["data"];
    return { data: extracted, images: topImages };
  } catch {
    return {
      data: { name: title || undefined, description: metaDesc || undefined },
      images: topImages,
    };
  }
}

function extractImageCandidates($: ReturnType<typeof cheerio.load>, baseUrl: string): string[] {
  const imgs: string[] = [];
  $("img").each((_, el) => {
    const src = $(el).attr("src") || $(el).attr("data-src");
    if (!src) return;
    const widthAttr = $(el).attr("width");
    const heightAttr = $(el).attr("height");
    const width = widthAttr ? parseInt(widthAttr, 10) : 0;
    const height = heightAttr ? parseInt(heightAttr, 10) : 0;
    if (width > 0 && width < 200) return;
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
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.byteLength; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode.apply(null, Array.from(chunk));
  }
  return btoa(binary);
}
