import { Hono } from "hono";
import type { CrawlRequest, CrawlResponse } from "./types";
import { crawl } from "./crawler";

type Env = { ANTHROPIC_API_KEY: string };

const app = new Hono<{ Bindings: Env }>();

app.get("/health", (c) => c.text("ok"));

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

export default app;
