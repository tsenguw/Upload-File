const fs = require("fs");
const path = require("path");

const projectRoot = path.resolve(__dirname, "..");
const runtimeRoot = path.join(projectRoot, "n8n-runtime");
const requiredFiles = [
	"node.exe",
	"node_modules/n8n/bin/n8n",
	"node_modules/sqlite3/build/Release/node_sqlite3.node",
	"node_modules/@n8n/ai-workflow-builder/dist/prompts/chains/parameter-updater/registry.js",
	"node_modules/@n8n/ai-workflow-builder/dist/prompts/chains/parameter-updater/examples/index.js",
];

const missingFiles = requiredFiles.filter((file) => !fs.existsSync(path.join(runtimeRoot, file)));
if (missingFiles.length > 0) {
	console.error(`Bundled runtime verification failed: ${missingFiles.join(", ")}`);
	process.exit(1);
}

console.log(`Bundled runtime verified: ${runtimeRoot}`);
