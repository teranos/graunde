import { type BuildContext, context } from "esbuild";
import sveltePlugin from "esbuild-svelte";
import { typescript } from "svelte-preprocess-esbuild";
import { Database } from "bun:sqlite";
import { watch } from "fs";
import { readFile } from "fs/promises";
import { join, resolve } from "path";

const PORT = 3100;
const PROJECT_ROOT = resolve(import.meta.dir, "..");
const DIST = resolve(import.meta.dir, "dist");
const DB_PATH = join(
  process.env.HOME ?? "",
  ".local/share/graunde/graunde.db"
);

// SSE clients for hot reload
const clients: Set<ReadableStreamDefaultController> = new Set();

function notifyClients() {
  for (const c of clients) {
    try {
      c.enqueue("data: reload\n\n");
    } catch {
      clients.delete(c);
    }
  }
}

// Incremental esbuild context
let ctx: BuildContext;
async function rebuild() {
  try {
    await ctx.rebuild();
    console.log("[tower] rebuilt");
    notifyClients();
  } catch (e) {
    console.error("[tower] build error:", e);
  }
}

ctx = await context({
  entryPoints: ["src/main.ts"],
  bundle: true,
  outfile: "dist/main.js",
  format: "esm",
  sourcemap: true,
  plugins: [
    sveltePlugin({
      preprocess: [typescript()],
      compilerOptions: { css: "injected", dev: true },
    }),
  ],
  logLevel: "warning",
});

// Initial build
await ctx.rebuild();
console.log("[tower] initial build done");

// Watch src/ for changes
watch(resolve(import.meta.dir, "src"), { recursive: true }, () => rebuild());
watch(resolve(import.meta.dir, "src/tower.css"), () => rebuild());

// Query fire counts from DB, bucketed into 7 daily bins
const BUCKET_COUNT = 7;

type FireInfo = {
  count: number;
  lastFired: string | null;
  buckets: number[]; // 7 daily counts, oldest first
};

function queryFires(): Record<string, FireInfo> {
  const result: Record<string, FireInfo> = {};
  const now = Date.now();
  const dayMs = 86400000;

  try {
    const db = new Database(DB_PATH);
    const rows = db
      .query(
        `SELECT attributes, timestamp
       FROM attestations
       WHERE predicates LIKE '%Graunded%'
       ORDER BY timestamp DESC`
      )
      .all() as { attributes: string; timestamp: string }[];

    for (const row of rows) {
      try {
        const attrs = JSON.parse(row.attributes);
        const name = attrs.control;
        if (!name) continue;

        if (!result[name]) {
          result[name] = { count: 0, lastFired: null, buckets: new Array(BUCKET_COUNT).fill(0) };
        }
        result[name].count++;
        if (!result[name].lastFired) {
          result[name].lastFired = row.timestamp;
        }

        // Bucket by day
        const ts = new Date(row.timestamp).getTime();
        const daysAgo = Math.floor((now - ts) / dayMs);
        const idx = BUCKET_COUNT - 1 - daysAgo;
        if (idx >= 0 && idx < BUCKET_COUNT) {
          result[name].buckets[idx]++;
        }
      } catch {}
    }
    db.close();
  } catch (e) {
    console.error("[tower] db error:", e);
  }
  return result;
}

const MIME: Record<string, string> = {
  ".html": "text/html",
  ".js": "application/javascript",
  ".css": "text/css",
  ".map": "application/json",
};

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;

    // API: fire counts
    if (path === "/api/fires") {
      return Response.json(queryFires());
    }

    // SSE: hot reload
    if (path === "/api/events") {
      const stream = new ReadableStream({
        start(controller) {
          clients.add(controller);
          controller.enqueue("data: connected\n\n");
        },
        cancel(controller) {
          clients.delete(controller as any);
        },
      });
      return new Response(stream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
        },
      });
    }

    // Textproto files from project root
    if (path.startsWith("/controls/") && path.endsWith(".textproto")) {
      try {
        const content = await readFile(join(PROJECT_ROOT, path), "utf-8");
        return new Response(content, {
          headers: { "Content-Type": "text/plain" },
        });
      } catch {
        return new Response("Not found", { status: 404 });
      }
    }

    // Static files from dist/ and tower root
    let filePath: string;
    if (path === "/" || path === "/index.html") {
      filePath = join(import.meta.dir, "index.html");
    } else if (path === "/tower.css") {
      filePath = join(import.meta.dir, "src", "tower.css");
    } else {
      filePath = join(DIST, path.slice(1));
    }

    try {
      const content = await readFile(filePath);
      const ext = "." + filePath.split(".").pop();
      return new Response(content, {
        headers: { "Content-Type": MIME[ext] ?? "application/octet-stream" },
      });
    } catch {
      return new Response("Not found", { status: 404 });
    }
  },
});

console.log(`[tower] http://localhost:${PORT}`);
