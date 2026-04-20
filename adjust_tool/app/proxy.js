const http = require("http");

const TARGET_ORIGIN = "https://api.adjust.com";
const PORT = 8787;
const upstreamCookieJar = new Map();

function writeCorsHeaders(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, x-csrf-token, X-CSRF-Token",
  );
  res.setHeader(
    "Access-Control-Allow-Methods",
    "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  );
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function splitSetCookieHeader(rawSetCookie) {
  if (!rawSetCookie) return [];
  return rawSetCookie.split(/,(?=\s*[^;,=\s]+=[^;,]+)/g);
}

function parseCookieHeader(cookieHeader) {
  const cookieMap = new Map();
  if (!cookieHeader) return cookieMap;

  cookieHeader.split(";").forEach((part) => {
    const trimmed = part.trim();
    if (!trimmed) return;
    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex <= 0) return;
    const key = trimmed.slice(0, separatorIndex).trim();
    const value = trimmed.slice(separatorIndex + 1).trim();
    if (!key) return;
    cookieMap.set(key, value);
  });

  return cookieMap;
}

function serializeCookieMap(cookieMap) {
  return Array.from(cookieMap.entries())
    .map(([key, value]) => `${key}=${value}`)
    .join("; ");
}

function mergeCookies(clientCookieHeader) {
  const merged = new Map(upstreamCookieJar);
  const clientCookies = parseCookieHeader(clientCookieHeader);
  clientCookies.forEach((value, key) => {
    merged.set(key, value);
  });
  return serializeCookieMap(merged);
}

function updateUpstreamCookieJar(headers) {
  let setCookieHeaders = [];
  if (typeof headers.getSetCookie === "function") {
    setCookieHeaders = headers.getSetCookie();
  } else {
    setCookieHeaders = splitSetCookieHeader(headers.get("set-cookie"));
  }

  setCookieHeaders.forEach((setCookieValue) => {
    const firstPart = setCookieValue.split(";")[0]?.trim();
    if (!firstPart) return;
    const separatorIndex = firstPart.indexOf("=");
    if (separatorIndex <= 0) return;
    const name = firstPart.slice(0, separatorIndex).trim();
    const value = firstPart.slice(separatorIndex + 1).trim();
    if (!name) return;

    if (!value) {
      upstreamCookieJar.delete(name);
      return;
    }

    upstreamCookieJar.set(name, value);
  });
}

http
  .createServer(async (req, res) => {
    writeCorsHeaders(res);

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    try {
      const targetUrl = `${TARGET_ORIGIN}${req.url}`;
      const bodyBuffer = await readRequestBody(req);
      const canSendBody = !["GET", "HEAD"].includes(req.method);

      const forwardHeaders = {
        "content-type": req.headers["content-type"] || "application/json",
      };

      if (req.headers.authorization) {
        forwardHeaders.authorization = req.headers.authorization;
      }
      if (req.headers["x-csrf-token"]) {
        forwardHeaders["x-csrf-token"] = req.headers["x-csrf-token"];
      }
      const mergedCookieHeader = mergeCookies(req.headers.cookie);
      if (mergedCookieHeader) {
        forwardHeaders.cookie = mergedCookieHeader;
      }

      const upstreamResponse = await fetch(targetUrl, {
        method: req.method,
        headers: forwardHeaders,
        body: canSendBody ? bodyBuffer : undefined,
      });
      updateUpstreamCookieJar(upstreamResponse.headers);

      const upstreamText = await upstreamResponse.text();
      const contentType =
        upstreamResponse.headers.get("content-type") || "application/json";

      res.writeHead(upstreamResponse.status, {
        "Content-Type": contentType,
      });
      res.end(upstreamText);
    } catch (error) {
      res.writeHead(500, {
        "Content-Type": "application/json",
      });
      res.end(
        JSON.stringify({
          message: "Proxy request failed",
          error: error.message,
        }),
      );
    }
  })
  .listen(PORT, () => {
    console.log(`Proxy server running at http://localhost:${PORT}`);
  });
