/**
 * Cloudflare Pages Function — `/api/*` → `linereader-ai.xreasayaz21.workers.dev/*`
 *
 * Türkiye'de bazı mobil operatörlerin `*.workers.dev` alan adını yavaşlatması
 * veya engellemesi durumunda mobil uygulamanın `line-reader.pages.dev/api/...`
 * üzerinden kesintisiz çalışmasını sağlar. GitHub push ile otomatik yayınlanır.
 */
const WORKER_ORIGIN = "https://linereader-ai.xreasayaz21.workers.dev";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Admin-Secret, If-None-Match",
};

export async function onRequest(context) {
  const { request, params } = context;
  const method = request.method.toUpperCase();

  if (method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  const incomingUrl = new URL(request.url);
  const segments = Array.isArray(params?.path)
    ? params.path
    : params?.path
      ? [params.path]
      : [];
  const targetPath = "/" + segments.join("/");
  const targetUrl = `${WORKER_ORIGIN}${targetPath}${incomingUrl.search}`;

  const forwardHeaders = new Headers();
  for (const name of [
    "authorization",
    "content-type",
    "accept",
    "x-admin-secret",
    "if-none-match",
  ]) {
    const val = request.headers.get(name);
    if (val) forwardHeaders.set(name, val);
  }

  const init = {
    method,
    headers: forwardHeaders,
    redirect: "follow",
  };
  if (method !== "GET" && method !== "HEAD") {
    init.body = await request.arrayBuffer();
  }

  const upstream = await fetch(targetUrl, init);
  const outHeaders = new Headers(upstream.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) {
    outHeaders.set(k, v);
  }

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: outHeaders,
  });
}
