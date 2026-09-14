#!/usr/bin/env node
/**
 * Capacitor plugin wiring/name checker.
 *
 * Enforces that runtime plugin name matches across:
 * - JS: registerPlugin('Name')
 * - Android: @CapacitorPlugin(name = "Name")
 * - iOS: CAPBridgedPlugin jsName = "Name"
 *
 * And (when iOS is declared in package.json capacitor config):
 * - CocoaPods podspec s.name matches SwiftPM Package(name: ...) and .library(name: ...)
 *
 * Usage:
 *   node scripts/check-capacitor-plugin-wiring.mjs            # checks current working dir
 *   node scripts/check-capacitor-plugin-wiring.mjs --dir path # checks given plugin dir
 */

import fs from "node:fs";
import path from "node:path";
import {
  exists,
  getCapacitorConfig,
  loadPluginPackage,
  parsePluginDirArgs,
  readText,
  reportFailures,
  walkFiles,
} from "./plugin-scan-fs.mjs";

function uniq(arr) {
  const out = [];
  for (const x of arr) {
    if (!x) continue;
    if (!out.includes(x)) out.push(x);
  }
  return out;
}

const args = parsePluginDirArgs(process.argv, "wiring");
const pluginDir = args.dir;
const pkg = loadPluginPackage(pluginDir, "wiring");
const cap = getCapacitorConfig(pkg);
const supportsAndroid = typeof cap.android === "object" && cap.android;
const supportsIos = typeof cap.ios === "object" && cap.ios;

// Not a Capacitor plugin package (e.g. meta/workspace package).
// We only enforce wiring rules for actual plugin packages declaring a `capacitor` config.
if (!supportsAndroid && !supportsIos) {
  process.exit(0);
}

// ---------------- JS (registerPlugin) ----------------
const jsSrcDir = path.join(pluginDir, "src");
let jsName = "";
if (exists(pluginDir, jsSrcDir)) {
  const jsFiles = walkFiles(pluginDir, jsSrcDir, [".ts", ".js"]);
  const reRegister = /registerPlugin(?:<[^>]*>)?\(\s*['"]([^'"]+)['"]/;
  for (const f of jsFiles) {
    const m = reRegister.exec(readText(pluginDir, f));
    if (m) {
      jsName = m[1];
      break;
    }
  }
}

// ---------------- Android (@CapacitorPlugin) ----------------
let androidNames = [];
if (supportsAndroid) {
  const androidMain = path.join(pluginDir, "android", "src", "main");
  const files = walkFiles(pluginDir, androidMain, [".java", ".kt"]);
  const foundAnnotations = [];
  for (const f of files) {
    const txt = readText(pluginDir, f);
    if (!txt.includes("@CapacitorPlugin")) continue;
    foundAnnotations.push(f);
    const m =
      /@CapacitorPlugin\(\s*name\s*=\s*"([^"]+)"/.exec(txt) ||
      /@CapacitorPlugin\(\s*name\s*=\s*([A-Za-z0-9_]+)\b/.exec(txt);
    if (m) androidNames.push(m[1]);
  }
  androidNames = uniq(androidNames);

  // Enforce explicit name attribute to prevent silent class-name drift.
  if (foundAnnotations.length && !androidNames.length) {
    console.error(
      `[wiring] ERROR: Android has @CapacitorPlugin but none specify name = \"...\". Add an explicit name to the plugin class.`
    );
    process.exit(1);
  }
}

// ---------------- iOS (jsName) ----------------
let iosJsNames = [];
if (supportsIos) {
  const iosDir = path.join(pluginDir, "ios");
  const scanRoot = exists(pluginDir, path.join(iosDir, "Sources"))
    ? path.join(iosDir, "Sources")
    : iosDir;
  const swiftFiles = walkFiles(pluginDir, scanRoot, [".swift"]);
  const reJsName = /\bjsName\s*=\s*"([^"]+)"/g;
  for (const f of swiftFiles) {
    const txt = readText(pluginDir, f);
    if (!txt.includes("jsName")) continue;
    let m;
    while ((m = reJsName.exec(txt))) iosJsNames.push(m[1]);
  }
  iosJsNames = uniq(iosJsNames);
}

// ---------------- Podspec/SPM ----------------
function parsePodspecName(pluginDir, podspecPath) {
  const txt = readText(pluginDir, podspecPath);
  const m = /\bs\.name\s*=\s*'([^']+)'/.exec(txt);
  return m ? m[1] : "";
}

function parseSpmNames(pluginDir, packageSwiftPath) {
  const txt = readText(pluginDir, packageSwiftPath);
  const pkg = /Package\(\s*name\s*:\s*"([^"]+)"/.exec(txt)?.[1] || "";
  const libs = [];
  const reLib = /\.library\(\s*name\s*:\s*"([^"]+)"/g;
  let m;
  while ((m = reLib.exec(txt))) libs.push(m[1]);
  return { pkgName: pkg, libNames: uniq(libs) };
}

// ---------------- Validate ----------------
const errors = [];

if (!jsName) {
  errors.push("JS: no registerPlugin('...') found under src/");
}

if (supportsAndroid) {
  if (!androidNames.length) errors.push("Android: missing @CapacitorPlugin(name = \"...\")");
  if (jsName && androidNames.length && androidNames.some((n) => n !== jsName)) {
    errors.push(`Android: @CapacitorPlugin(name)=${JSON.stringify(androidNames)} != JS registerPlugin=${jsName}`);
  }
}

if (supportsIos) {
  if (!iosJsNames.length) errors.push('iOS: missing jsName = "..." in Swift sources');
  if (jsName && iosJsNames.length && iosJsNames.some((n) => n !== jsName)) {
    errors.push(`iOS: jsName=${JSON.stringify(iosJsNames)} != JS registerPlugin=${jsName}`);
  }

  const podspecs = fs
    .readdirSync(pluginDir, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith(".podspec"))
    .map((e) => path.join(pluginDir, e.name))
    .sort();
  if (!podspecs.length) errors.push("iOS: missing *.podspec at plugin root");
  if (podspecs.length > 1) errors.push(`iOS: multiple podspecs at plugin root: ${podspecs.map((p) => path.basename(p))}`);

  const pkgSwift = path.join(pluginDir, "Package.swift");
  if (!exists(pluginDir, pkgSwift)) {
    errors.push("iOS: missing Package.swift at plugin root");
  } else if (podspecs.length) {
    const podName = parsePodspecName(pluginDir, podspecs[0]);
    const { pkgName, libNames } = parseSpmNames(pluginDir, pkgSwift);
    if (!podName) errors.push("Podspec: missing s.name = '...'");
    if (!pkgName) errors.push('SPM: missing Package(name: "...")');
    if (podName && pkgName && podName !== pkgName) {
      errors.push(`Podspec: s.name=${podName} != Package(name)=${pkgName}`);
    }
    if (pkgName && libNames.length && !libNames.includes(pkgName)) {
      errors.push(`SPM: Package(name)=${pkgName} not present in .library(name) list ${JSON.stringify(libNames)}`);
    }
  }
}

reportFailures("wiring", pluginDir, errors);

process.exit(0);
