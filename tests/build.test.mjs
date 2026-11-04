// Self test for build.mjs's consistency checks (`node --test tests/*.test.mjs`).
// Each case builds a throwaway plugin repo and runs `node build.mjs --check-only` in it.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const buildMjs = resolve(dirname(fileURLToPath(import.meta.url)), "..", "build.mjs");
const roots = [];
after(() => roots.forEach((dir) => rmSync(dir, { recursive: true, force: true })));

const BIN = "opendeck-demo";
const TRIPLE = "x86_64-unknown-linux-gnu";

// A consistent plugin repo; `overrides` replaces whole files (path -> text).
function fixture(overrides = {}) {
	const root = mkdtempSync(join(tmpdir(), "build-mjs-test-"));
	roots.push(root);
	const manifest = {
		Version: "1.2.3",
		Actions: [{ UUID: "com.jfms7s.demo.first" }, { UUID: "com.jfms7s.demo.second" }],
		CodePaths: { [TRIPLE]: `${BIN}-${TRIPLE}` },
		CodePathLin: `${BIN}-${TRIPLE}`,
	};
	const files = {
		"Cargo.toml": `[package]\nname = "${BIN}"\nversion = "1.2.3"\n`,
		"assets/manifest.json": JSON.stringify(manifest),
		"src/first.rs": 'impl Action for First {\n    const UUID: &\'static str = "com.jfms7s.demo.first";\n}\n',
		...overrides,
	};
	for (const [path, text] of Object.entries(files)) {
		mkdirSync(dirname(join(root, path)), { recursive: true });
		writeFileSync(join(root, path), text);
	}
	return root;
}

function check(root, ...extra) {
	const result = spawnSync(process.execPath, [buildMjs, "--check-only", ...extra], { cwd: root, encoding: "utf8" });
	return { status: result.status, out: `${result.stdout}${result.stderr}` };
}

test("a consistent repo passes", () => {
	const { status, out } = check(fixture());
	assert.equal(status, 0, out);
	assert.match(out, /metadata is consistent/);
});

test("a const UUID the manifest declares passes, however it is formatted", () => {
	const src = 'const UUID: &str = "com.jfms7s.demo.second";\nconst  UUID : & \'static  str  =  "com.jfms7s.demo.first";\n';
	assert.equal(check(fixture({ "src/nested/more.rs": src })).status, 0);
});

test("a const UUID in the namespace that the manifest does not declare fails", () => {
	const { status, out } = check(fixture({ "src/third.rs": 'const UUID: &str = "com.jfms7s.demo.third";\n' }));
	assert.equal(status, 1);
	assert.match(out, /com\.jfms7s\.demo\.third/);
	assert.doesNotMatch(out, /outside the plugin namespace/);
});

test("a const UUID with a typo in the plugin segment fails", () => {
	const { status, out } = check(fixture({ "src/typo.rs": 'const UUID: &\'static str = "com.jfms7s.demoo.first";\n' }));
	assert.equal(status, 1);
	assert.match(out, /com\.jfms7s\.demoo\.first.*outside the plugin namespace com\.jfms7s\.demo/);
});

test("the family prefix is matched case-insensitively", () => {
	assert.equal(check(fixture({ "src/case.rs": 'const UUID: &str = "COM.JFMS7S.demo.first";\n' })).status, 1);
});

test("a UUID outside the project family (a test double) is ignored", () => {
	const src = 'mod tests {\n    const UUID: &\'static str = "test.echo";\n    const UUID: &str = "com.example.other.thing";\n}\n';
	assert.equal(check(fixture({ "src/double.rs": src })).status, 0);
});

test("a UUID that is not written as a const literal is not looked at", () => {
	assert.equal(check(fixture({ "src/computed.rs": 'let uuid = "com.jfms7s.nothing.here";\nconst UUID: &str = K::UUID;\n' })).status, 0);
});

test("Cargo.toml and manifest.json must agree on the version", () => {
	const { status, out } = check(fixture({ "Cargo.toml": `[package]\nname = "${BIN}"\nversion = "1.2.4"\n` }));
	assert.equal(status, 1);
	assert.match(out, /version mismatch/);
});

test("--tag must be v<version>", () => {
	const root = fixture();
	assert.equal(check(root, "--tag", "v1.2.3").status, 0);
	assert.equal(check(root, "--tag", "v1.2.4").status, 1);
});

test("CodePaths files must be named <bin>-<triple>", () => {
	const manifest = JSON.stringify({
		Version: "1.2.3",
		Actions: [{ UUID: "com.jfms7s.demo.first" }],
		CodePaths: { [TRIPLE]: "wrong-name" },
	});
	assert.equal(check(fixture({ "assets/manifest.json": manifest })).status, 1);
});

test("an action outside the plugin namespace fails", () => {
	const manifest = JSON.stringify({
		Version: "1.2.3",
		Actions: [{ UUID: "com.jfms7s.demo.first" }, { UUID: "com.jfms7s.other.second" }],
		CodePaths: { [TRIPLE]: `${BIN}-${TRIPLE}` },
	});
	assert.equal(check(fixture({ "assets/manifest.json": manifest })).status, 1);
});
