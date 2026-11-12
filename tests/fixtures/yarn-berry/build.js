// Fixture build: writes dist/out.txt. Plain Node, so it runs the same on every OS.
const fs = require("node:fs");

fs.mkdirSync("dist", { recursive: true });
fs.writeFileSync("dist/out.txt", "built by the yarn-berry fixture\n");
