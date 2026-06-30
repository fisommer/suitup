/**
 * Pull variant selections (color, size) out of a product URL.
 *
 * Retailers encode the *selected* variant in the URL even when the JSON-LD
 * ships only the default product. We grab the raw code here; the structured
 * extractor will try to resolve it to a human-readable label via `hasVariant`.
 *
 * Matching is case-insensitive — retailers use wildly inconsistent casing
 * (colorCode vs colourcode vs ColorDisplayCode etc.).
 */
export function extractVariantsFromURL(url: string): { color?: string; size?: string } {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return {};
  }

  // Lowercase index of search params for case-insensitive lookup.
  const paramsLower = new Map<string, string>();
  parsed.searchParams.forEach((value, key) => {
    paramsLower.set(key.toLowerCase(), value);
  });

  // Common keys observed across Uniqlo / Zalando / H&M / Adidas / COS / Zara / Mango.
  // All entries here should already be lowercased.
  const COLOR_KEYS = [
    "color",
    "colour",
    "colorcode",
    "colourcode",
    "colordisplaycode",
    "colourdisplaycode",
    "selectedcolor",
    "variant",
    "v1",
  ];
  const SIZE_KEYS = [
    "size",
    "sizecode",
    "sizedisplaycode",
    "selectedsize",
  ];

  const colorKey = COLOR_KEYS.find((k) => paramsLower.has(k));
  const sizeKey = SIZE_KEYS.find((k) => paramsLower.has(k));

  const color = colorKey ? paramsLower.get(colorKey) : undefined;
  const size = sizeKey ? paramsLower.get(sizeKey) : undefined;

  return {
    color: color?.trim() || undefined,
    size: size?.trim() || undefined,
  };
}
