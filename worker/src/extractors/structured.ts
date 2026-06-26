import * as cheerio from "cheerio";
import type { CrawlResponse } from "../types";

type CheerioRoot = ReturnType<typeof cheerio.load>;

export function extractStructured(
  html: string,
  baseUrl: string
): { data: CrawlResponse["data"]; images: string[] } {
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
              const value = Number(offer.price);
              if (Number.isFinite(value)) {
                data.price = { value, currency: offer.priceCurrency };
              }
            }
          }
          if (p.color && !data.colors) {
            data.colors = Array.isArray(p.color) ? p.color : [p.color];
          }
          if (p.material && !data.materials) {
            data.materials = Array.isArray(p.material) ? p.material : [p.material];
          }
          if (p.description && !data.description) data.description = p.description;
          if (p.category && !data.category) {
            data.category = Array.isArray(p.category) ? p.category[0] : p.category;
          }
        }
      }
    } catch {
      // tolerate malformed JSON-LD
    }
  });

  // 2. OpenGraph fallbacks
  if (!data.name) {
    data.name = $('meta[property="og:title"]').attr("content") ?? undefined;
  }
  if (!data.description) {
    data.description = $('meta[property="og:description"]').attr("content") ?? undefined;
  }
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
    return node["@graph"].filter((n: any) => n && n["@type"] === "Product");
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
