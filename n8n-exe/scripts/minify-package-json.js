const fs = require("fs");
const path = require("path");

const root = process.argv[2];
if (!root) {
	throw new Error("Usage: minify-package-json.js <node_modules-path>");
}

let filesProcessed = 0;
let bytesSaved = 0;
const stack = [root];

while (stack.length > 0) {
	const directory = stack.pop();
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		const entryPath = path.join(directory, entry.name);
		if (entry.isDirectory()) {
			stack.push(entryPath);
			continue;
		}
		if (!entry.isFile() || entry.name !== "package.json") continue;

		const original = fs.readFileSync(entryPath, "utf8");
		try {
			const parsed = JSON.parse(original.replace(/^\uFEFF/, ""));
			const minified = JSON.stringify(parsed);
			if (Buffer.byteLength(minified, "utf8") < Buffer.byteLength(original, "utf8")) {
				fs.writeFileSync(entryPath, minified, "utf8");
				bytesSaved += Buffer.byteLength(original, "utf8") - Buffer.byteLength(minified, "utf8");
			}
			filesProcessed += 1;
		} catch {
			// Invalid JSON is left untouched. It may be an intentionally non-standard package manifest.
		}
	}
}

process.stdout.write(`${JSON.stringify({ filesProcessed, bytesSaved })}\n`);
