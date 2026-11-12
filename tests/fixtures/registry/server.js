// A tiny npm registry for the tests. It serves one scoped package and answers 401 to
// every request that does not carry the right bearer token, the way a private registry
// does. It listens on a free port on 127.0.0.1 and writes the port to a file.
//
// Usage: node server.js <package.tgz> <token> <port-file> <request-log>
"use strict";
const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");

const [tarballPath, token, portFile, requestLog] = process.argv.slice(2);
const tarball = fs.readFileSync(tarballPath);
const integrity = "sha512-" + crypto.createHash("sha512").update(tarball).digest("base64");
const shasum = crypto.createHash("sha1").update(tarball).digest("hex");

const server = http.createServer((request, response) => {
  const authorized = request.headers.authorization === `Bearer ${token}`;
  fs.appendFileSync(requestLog, `${request.method} ${request.url} ${authorized ? "authorized" : "denied"}\n`);

  if (!authorized) {
    response.writeHead(401, { "content-type": "application/json" });
    response.end(JSON.stringify({ error: "authentication required" }));
    return;
  }

  if (request.url === "/@nab-test%2fprivate-pkg" || request.url === "/@nab-test/private-pkg") {
    const port = server.address().port;
    response.writeHead(200, { "content-type": "application/json" });
    response.end(
      JSON.stringify({
        name: "@nab-test/private-pkg",
        "dist-tags": { latest: "1.0.0" },
        versions: {
          "1.0.0": {
            name: "@nab-test/private-pkg",
            version: "1.0.0",
            dist: {
              tarball: `http://127.0.0.1:${port}/tarballs/private-pkg-1.0.0.tgz`,
              shasum,
              integrity,
            },
          },
        },
      }),
    );
    return;
  }

  if (request.url === "/tarballs/private-pkg-1.0.0.tgz") {
    response.writeHead(200, { "content-type": "application/octet-stream" });
    response.end(tarball);
    return;
  }

  response.writeHead(404);
  response.end();
});

server.listen(0, "127.0.0.1", () => {
  fs.writeFileSync(portFile, String(server.address().port));
});
