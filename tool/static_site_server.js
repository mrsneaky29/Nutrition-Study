const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

function option(name, fallback) {
  const prefix = `--${name}=`;
  const argument = process.argv.slice(2).find((value) => value.startsWith(prefix));
  return argument ? argument.slice(prefix.length) : fallback;
}

const root = path.resolve(option("root", "build/collector_web"));
const port = Number(option("port", "8085"));
const host = option("host", "127.0.0.1");

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("--port must be an integer from 1 to 65535.");
}
if (!fs.existsSync(path.join(root, "index.html"))) {
  throw new Error(`No built website found at ${root}.`);
}

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".wasm", "application/wasm"],
]);

http.createServer((request, response) => {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
  } catch {
    response.writeHead(400).end("Bad request");
    return;
  }
  const requested = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  let file = path.resolve(root, requested);
  if (!file.startsWith(`${root}${path.sep}`) && file !== root) {
    response.writeHead(403).end("Forbidden");
    return;
  }
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
    file = path.join(root, "index.html");
  }
  response.writeHead(200, {
    "Content-Type": contentTypes.get(path.extname(file)) || "application/octet-stream",
    "Cache-Control": file.endsWith("index.html") ? "no-cache" : "public, max-age=3600",
  });
  fs.createReadStream(file).pipe(response);
}).listen(port, host, () => {
  console.log(`Serving ${root} at http://${host}:${port}`);
});
