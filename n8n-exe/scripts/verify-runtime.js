const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const projectRoot = path.resolve(__dirname, "..");
const archivePath = path.join(projectRoot, "n8n.7z");
const archiverPath = path.join(projectRoot, "7za.exe");
const manifestPath = path.join(projectRoot, "runtime-manifest.json");

function fail(message) {
	console.error(`Runtime verification failed: ${message}`);
	process.exit(1);
}

function sha256File(filePath) {
	const hash = crypto.createHash("sha256");
	const file = fs.openSync(filePath, "r");
	const buffer = Buffer.allocUnsafe(1024 * 1024);
	try {
		let bytesRead;
		let position = 0;
		do {
			bytesRead = fs.readSync(file, buffer, 0, buffer.length, position);
			if (bytesRead > 0) {
				hash.update(buffer.subarray(0, bytesRead));
				position += bytesRead;
			}
		} while (bytesRead > 0);
	} finally {
		fs.closeSync(file);
	}
	return hash.digest("hex");
}

if (![archivePath, archiverPath, manifestPath].every(fs.existsSync)) {
	fail("archive, archiver, or runtime manifest is missing");
}

let manifest;
try {
	manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
} catch (error) {
	fail(`invalid runtime manifest: ${error.message}`);
}

if (!Array.isArray(manifest.requiredFiles) || !manifest.runtimeId?.startsWith("sha256:")) {
	fail("runtime manifest has an invalid schema");
}

const hash = sha256File(archivePath);
if (manifest.runtimeId !== `sha256:${hash}`) {
	fail("runtime manifest does not match n8n.7z");
}

const result = spawnSync(archiverPath, ["l", archivePath], {
	encoding: "utf8",
	windowsHide: true,
	maxBuffer: 64 * 1024 * 1024,
});
if (result.error || result.status !== 0) {
	fail(result.error?.message ?? result.stderr ?? "could not list n8n.7z");
}

const listing = result.stdout.replace(/\//g, "\\");
for (const requiredFile of manifest.requiredFiles) {
	if (!listing.includes(requiredFile.replace(/\//g, "\\"))) {
		fail(`archive is missing ${requiredFile}`);
	}
}

console.log(`Runtime verified: ${manifest.runtimeId}`);
