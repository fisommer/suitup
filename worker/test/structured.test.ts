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
    expect(r.data.name).toBe("COS Linen Shirt");
    expect(r.data.brand).toBe("COS");
    expect(r.data.price).toEqual({ value: 69, currency: "EUR" });
    expect(r.data.colors).toEqual(["beige"]);
    expect(r.data.materials).toEqual(["100% linen"]);
    expect(r.images).toHaveLength(2);
    expect(r.images[0]).toBe("https://example.com/shirt-1.jpg");
  });

  it("falls back to OpenGraph when no JSON-LD", () => {
    const html = `<html><head>
      <meta property="og:title" content="Some Shirt" />
      <meta property="og:image" content="/img/shirt.jpg" />
      <meta property="og:description" content="A nice shirt" />
    </head></html>`;
    const r = extractStructured(html, "https://shop.test/p/1");
    expect(r.data.name).toBe("Some Shirt");
    expect(r.data.description).toBe("A nice shirt");
    expect(r.images[0]).toBe("https://shop.test/img/shirt.jpg");
  });

  it("absolutizes relative image URLs", () => {
    const html = `<html><head>
      <script type="application/ld+json">{
        "@type":"Product",
        "name":"X",
        "image":"/relative.jpg"
      }</script>
    </head></html>`;
    const r = extractStructured(html, "https://shop.test/p/abc");
    expect(r.images[0]).toBe("https://shop.test/relative.jpg");
  });

  it("tolerates malformed JSON-LD without crashing", () => {
    const html = `<html><head>
      <script type="application/ld+json">{ not valid json }</script>
      <meta property="og:title" content="Fallback Title" />
    </head></html>`;
    const r = extractStructured(html, "https://shop.test/");
    expect(r.data.name).toBe("Fallback Title");
  });

  it("unwraps @graph arrays", () => {
    const html = `<html><head>
      <script type="application/ld+json">{
        "@context":"https://schema.org",
        "@graph":[
          {"@type":"Organization","name":"Shop"},
          {"@type":"Product","name":"Inner Product","image":"https://example.com/i.jpg"}
        ]
      }</script>
    </head></html>`;
    const r = extractStructured(html, "https://example.com/");
    expect(r.data.name).toBe("Inner Product");
    expect(r.images[0]).toBe("https://example.com/i.jpg");
  });
});
