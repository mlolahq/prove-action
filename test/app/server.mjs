// A page and an API, small enough to read in one look: what the action's own
// test proves a contract against. `node test/app/server.mjs` (PORT, default 4330).
import { createServer } from "node:http";

const page = `<!doctype html>
<html lang="en">
  <head><meta charset="utf-8"><title>Greeter</title></head>
  <body>
    <h1>Greeter</h1>
    <label>Your name <input id="name" value=""></label>
    <button type="button" id="greet">Say hello</button>
    <p id="out" role="status"></p>
    <script>
      document.getElementById("greet").addEventListener("click", () => {
        const name = document.getElementById("name").value.trim();
        document.getElementById("out").textContent = name ? "Hello, " + name + "!" : "Please enter your name.";
      });
    </script>
  </body>
</html>`;

const port = Number(process.env.PORT ?? 4330);
createServer((req, res) => {
  if (req.url === "/api/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true }));
  } else if (req.url === "/") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(page);
  } else {
    res.writeHead(404).end("not found");
  }
}).listen(port, "127.0.0.1", () => console.log(`greeter on http://127.0.0.1:${port}`));
