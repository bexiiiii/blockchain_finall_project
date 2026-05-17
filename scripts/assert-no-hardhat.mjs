import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const ignored = new Set([".git", "node_modules", "lib", "out", "cache", "broadcast", "dist"]);
const forbiddenFiles = [];

function walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (ignored.has(entry)) continue;
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      walk(full);
      continue;
    }
    if (/^hardhat(\.config)?\./i.test(entry) || /^hardhat\./i.test(entry)) {
      forbiddenFiles.push(full);
    }
  }
}

walk(root);

const pkgPath = join(root, "package.json");
const packageJson = existsSync(pkgPath) ? JSON.parse(readFileSync(pkgPath, "utf8")) : {};
const deps = { ...(packageJson.dependencies ?? {}), ...(packageJson.devDependencies ?? {}) };
const hardhatDeps = Object.keys(deps).filter((name) => name.toLowerCase().includes("hardhat"));

if (forbiddenFiles.length > 0 || hardhatDeps.length > 0) {
  console.error("Hardhat is intentionally forbidden in this project.");
  for (const file of forbiddenFiles) console.error(`Forbidden file: ${file}`);
  for (const dep of hardhatDeps) console.error(`Forbidden dependency: ${dep}`);
  process.exit(1);
}
