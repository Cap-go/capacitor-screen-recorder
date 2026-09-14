import fs from "node:fs";
import path from "node:path";

export const DEFAULT_SKIP_DIRS = new Set([
  "node_modules",
  "dist",
  "build",
  ".build",
  ".gradle",
  "Pods",
  "DerivedData",
  ".swiftpm",
  ".git",
]);

export const CAP9_SKIP_DIRS = new Set([...DEFAULT_SKIP_DIRS, "example-app"]);

export function resolveInsideRoot(rootDir, targetPath) {
  const root = path.resolve(rootDir);
  const target = path.resolve(targetPath);
  const rel = path.relative(root, target);
  if (rel.startsWith("..") || path.isAbsolute(rel)) {
    return null;
  }
  return target;
}

export function resolvePluginDir(rawDir, logTag) {
  const resolved = path.resolve(rawDir);
  const rel = path.relative(process.cwd(), resolved);
  if (rel.startsWith("..") || path.isAbsolute(rel)) {
    console.error(`[${logTag}] ERROR: plugin dir must stay inside ${process.cwd()}`);
    process.exit(2);
  }
  return resolved;
}

export function readText(pluginDir, p) {
  const safe = resolveInsideRoot(pluginDir, p);
  if (!safe) {
    return "";
  }
  try {
    return fs.readFileSync(safe, "utf8");
  } catch {
    return "";
  }
}

export function exists(pluginDir, p) {
  const safe = resolveInsideRoot(pluginDir, p);
  if (!safe) {
    return false;
  }
  try {
    fs.accessSync(safe);
    return true;
  } catch {
    return false;
  }
}

function pushChildDir(pluginDir, dir, name, skipDirs, stack) {
  if (skipDirs.has(name)) {
    return;
  }
  const next = resolveInsideRoot(pluginDir, path.join(dir, name));
  if (next) {
    stack.push(next);
  }
}

function pushIfMatchingFile(pluginDir, dir, name, exts, out) {
  for (const ext of exts) {
    if (!name.endsWith(ext)) {
      continue;
    }
    const filePath = resolveInsideRoot(pluginDir, path.join(dir, name));
    if (filePath) {
      out.push(filePath);
    }
    return;
  }
}

function visitDirEntry(pluginDir, dir, entry, exts, skipDirs, stack, out) {
  if (entry.isDirectory()) {
    pushChildDir(pluginDir, dir, entry.name, skipDirs, stack);
    return;
  }
  if (!entry.isFile()) {
    return;
  }
  pushIfMatchingFile(pluginDir, dir, entry.name, exts, out);
}

export function walkFiles(pluginDir, rootDir, exts, skipDirs = DEFAULT_SKIP_DIRS) {
  const safeRoot = resolveInsideRoot(pluginDir, rootDir);
  if (!safeRoot) {
    return [];
  }

  const out = [];
  const stack = [safeRoot];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      visitDirEntry(pluginDir, dir, entry, exts, skipDirs, stack, out);
    }
  }
  out.sort((a, b) => a.localeCompare(b));
  return out;
}

export function parsePluginDirArgs(argv, logTag) {
  const out = { dir: resolvePluginDir(process.cwd(), logTag) };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dir" || a === "--pluginDir") {
      out.dir = resolvePluginDir(argv[++i] || ".", logTag);
    }
  }
  return out;
}

export function loadPluginPackage(pluginDir, logTag) {
  const pkgPath = path.join(pluginDir, "package.json");
  if (!exists(pluginDir, pkgPath)) {
    console.error(`[${logTag}] ERROR: missing package.json in ${pluginDir}`);
    process.exit(2);
  }
  try {
    return JSON.parse(readText(pluginDir, pkgPath));
  } catch (e) {
    console.error(`[${logTag}] ERROR: invalid package.json (${pkgPath}): ${e?.message || e}`);
    process.exit(2);
  }
}

export function getCapacitorConfig(pkg) {
  return typeof pkg.capacitor === "object" && pkg.capacitor ? pkg.capacitor : {};
}

export function reportFailures(logTag, pluginDir, messages) {
  if (!messages.length) {
    return;
  }
  const relDir = path.relative(process.cwd(), pluginDir) || ".";
  console.error(`[${logTag}] FAIL in ${relDir}`);
  for (const message of messages) {
    console.error(`- ${message}`);
  }
  process.exit(1);
}
