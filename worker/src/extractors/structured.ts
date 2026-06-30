import * as cheerio from "cheerio";
import type { CrawlResponse } from "../types";

type CheerioRoot = ReturnType<typeof cheerio.load>;

export interface StructuredResult {
  data: CrawlResponse["data"];
  /** Ordered: real product photos first, then non-logo OG/Twitter cards. */
  images: string[];
  /**
   * Maps raw variant codes (from URL params) to readable labels.
   * Built from JSON-LD `hasVariant` arrays when present.
   */
  variantLookup?: {
    color?: Record<string, string>;
    size?: Record<string, string>;
  };
}

const SOCIAL_FILENAME_REJECT = /logo|social|placeholder|default|avatar|share[-_]?card|og[-_]?image/i;

export function extractStructured(html: string, baseUrl: string): StructuredResult {
  const $ = cheerio.load(html);
  const productImages: string[] = [];
  const socialImages: string[] = [];
  const seen = new Set<string>();
  const data: CrawlResponse["data"] = {};
  const colorLookup: Record<string, string> = {};
  const sizeLookup: Record<string, string> = {};

  const addProductImage = (raw: string) => {
    const abs = absolutize(raw, baseUrl);
    if (!seen.has(abs)) {
      seen.add(abs);
      productImages.push(abs);
    }
  };
  const addSocialImage = (raw: string) => {
    const abs = absolutize(raw, baseUrl);
    if (!seen.has(abs) && !looksLikeSocialCardJunk(abs)) {
      seen.add(abs);
      socialImages.push(abs);
    }
  };

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
            imgs.forEach((i: string) => addProductImage(i));
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

          // Build variant lookup tables from `hasVariant`. Variants typically declare
          // their own `sku`, `color`, `size`, and sometimes their own `image`.
          if (Array.isArray(p.hasVariant)) {
            for (const v of p.hasVariant) {
              const key = v?.sku ?? v?.identifier ?? v?.productID;
              if (typeof key === "string" && typeof v?.color === "string") {
                colorLookup[key] = v.color;
              }
              if (typeof key === "string" && typeof v?.size === "string") {
                sizeLookup[key] = v.size;
              }
              if (typeof v?.image === "string") addProductImage(v.image);
              if (Array.isArray(v?.image)) v.image.forEach((i: string) => addProductImage(i));
            }
          }
        }
      }
    } catch {
      // tolerate malformed JSON-LD
    }
  });

  // 2. OpenGraph fallbacks — fields, then images (social-bucket).
  if (!data.name) {
    data.name = $('meta[property="og:title"]').attr("content") ?? undefined;
  }
  if (!data.description) {
    data.description = $('meta[property="og:description"]').attr("content") ?? undefined;
  }
  const ogImage = $('meta[property="og:image"]').attr("content");
  if (ogImage) addSocialImage(ogImage);

  // 3. Twitter card image (social-bucket).
  const twImage = $('meta[name="twitter:image"]').attr("content");
  if (twImage) addSocialImage(twImage);

  // Product images ranked above social images. Social images are only kept as
  // fallbacks when no JSON-LD product photos exist.
  const images = productImages.length > 0 ? [...productImages, ...socialImages] : socialImages;

  const variantLookup =
    Object.keys(colorLookup).length || Object.keys(sizeLookup).length
      ? {
          color: Object.keys(colorLookup).length ? colorLookup : undefined,
          size: Object.keys(sizeLookup).length ? sizeLookup : undefined,
        }
      : undefined;

  return { data, images, variantLookup };
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

function looksLikeSocialCardJunk(url: string): boolean {
  try {
    const u = new URL(url);
    const filename = u.pathname.split("/").pop() ?? "";
    return SOCIAL_FILENAME_REJECT.test(filename);
  } catch {
    return SOCIAL_FILENAME_REJECT.test(url);
  }
}
