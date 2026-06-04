import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const artifactDir = path.join(repoRoot, ".agent", "tmp", "desktop-visual-qa");
const screenshotPath = path.join(artifactDir, "desktop-pre190-pass.png");
const manifestPath = path.join(artifactDir, "manifest.json");
const scenario = "desktop-visual-qa";
const token_printed = false;
const requiredText = [
  "SkyBridge Desktop",
  "Pre-190 PASS",
  "STANDBY / READ ONLY",
  "HEARTBEAT ONLY MUTATION",
  "EXECUTION DISABLED",
  "super-190-campaign-run-report-evidence-ledger",
  "Active tasks",
  "0",
  "Stale leases",
  "Token printed",
  "false",
];

const args = new Set(process.argv.slice(2));
const requirePlaywright = args.has("--require-playwright");
const skipWhenUnavailable = args.has("--skip-when-unavailable");
const webBase = readArg("--web-base") ?? "http://127.0.0.1:1420";
const origin = new URL(webBase).origin;
const targetUrl = `${origin}/?fixture=desktop-pre190-pass`;
let serverProcess = null;

function readArg(name) {
  const prefix = `${name}=`;
  const found = process.argv.slice(2).find((arg) => arg.startsWith(prefix));
  return found ? found.slice(prefix.length) : null;
}

function isLoopback(urlText) {
  const url = new URL(urlText);
  return ["localhost", "127.0.0.1", "::1", "[::1]"].includes(url.hostname);
}

function emit(result) {
  process.stdout.write(`${JSON.stringify({ ...result, scenario, token_printed })}\n`);
}

function fail(message) {
  emit({ ok: false, skipped: false, error: message, artifact_dir: artifactDir });
  process.exitCode = 1;
}

function tokenPattern() {
  return /(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)/i;
}

async function canFetch(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(1500) });
    return response.ok;
  } catch {
    return false;
  }
}

async function waitForServer(url) {
  const deadline = Date.now() + 45_000;
  while (Date.now() < deadline) {
    if (await canFetch(url)) {
      return true;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return false;
}

async function ensureServer() {
  if (await canFetch(origin)) {
    return { started: false };
  }
  serverProcess = spawn("corepack", ["pnpm", "-C", "apps/desktop", "dev"], {
    cwd: repoRoot,
    shell: true,
    stdio: "ignore",
    windowsHide: true,
  });
  const ready = await waitForServer(origin);
  if (!ready) {
    throw new Error("Desktop Vite server did not become ready on loopback.");
  }
  return { started: true };
}

async function loadPlaywright() {
  try {
    return await import("playwright");
  } catch (error) {
    if (requirePlaywright) {
      throw new Error(`Playwright is required but unavailable: ${error.message}`);
    }
    if (skipWhenUnavailable) {
      emit({
        ok: true,
        skipped: true,
        reason: "Playwright unavailable",
        artifact_dir: artifactDir,
      });
      process.exit(0);
    }
    throw new Error(`Playwright unavailable: ${error.message}`);
  }
}

async function main() {
  if (!isLoopback(webBase)) {
    throw new Error(`Refusing non-loopback desktop visual QA base: ${webBase}`);
  }

  await mkdir(artifactDir, { recursive: true });
  const { chromium } = await loadPlaywright();
  const server = await ensureServer();
  const consoleErrors = [];
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1100, height: 900 } });
    page.on("console", (message) => {
      if (message.type() === "error") {
        consoleErrors.push(message.text());
      }
    });
    await page.goto(targetUrl, { waitUntil: "networkidle" });
    const bodyText = await page.locator("body").innerText();
    if (!bodyText || bodyText.trim().length < 80) {
      throw new Error("Desktop fixture page appears blank.");
    }
    const missing = requiredText.filter((text) => !bodyText.includes(text));
    if (missing.length > 0) {
      throw new Error(`Desktop fixture missing required text: ${missing.join(", ")}`);
    }
    if (consoleErrors.length > 0) {
      throw new Error(`Browser console errors: ${consoleErrors.join(" | ")}`);
    }
    if (tokenPattern().test(bodyText)) {
      throw new Error("Rendered body contains token-looking or Authorization-looking text.");
    }
    await page.screenshot({ path: screenshotPath, fullPage: true });
  } finally {
    await browser.close();
    if (serverProcess) {
      serverProcess.kill();
    }
  }

  const manifest = {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    fixture_only: true,
    production_endpoint_used: false,
    web_base_origin: origin,
    screenshots: [path.relative(artifactDir, screenshotPath)],
    required_text: requiredText,
    token_printed,
    server_started: server.started,
  };
  const manifestText = JSON.stringify(manifest, null, 2);
  if (tokenPattern().test(manifestText)) {
    throw new Error("Manifest contains token-looking or Authorization-looking text.");
  }
  await writeFile(manifestPath, manifestText);
  emit({
    ok: true,
    skipped: false,
    artifact_dir: artifactDir,
    manifest: manifestPath,
    screenshots: [screenshotPath],
  });
}

main().catch((error) => {
  if (serverProcess) {
    serverProcess.kill();
  }
  fail(error.message);
});
