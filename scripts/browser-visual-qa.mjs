import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const webBase = process.env.SKYBRIDGE_VISUAL_QA_WEB_BASE ?? "http://127.0.0.1:3000";
const artifactDir = process.env.SKYBRIDGE_VISUAL_QA_ARTIFACT_DIR ?? ".agent/tmp/browser-visual-qa";
const webBaseUrl = new URL(webBase);

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(webBaseUrl.hostname)) {
  throw new Error(`[browser-visual-qa] refusing non-loopback web base: ${webBaseUrl.origin}`);
}

const { chromium } = await import("playwright");

const requiredConsoleText = [
  "SkyBridge Agent Hub",
  "Daily operator picture",
  "Open PR/CI",
  "Auto-merge",
  "Hermes"
];

const viewports = [
  { name: "overview-desktop", path: "/#/overview", width: 1440, height: 1000, requiredText: requiredConsoleText },
  { name: "campaign-queue-desktop", path: "/#/campaign-queue", width: 1440, height: 1000, requiredText: ["Campaign Queue", "Queue Control Readiness", "worker_offline", "Start One disabled"] },
  { name: "pr-ci-desktop", path: "/#/pr-ci", width: 1440, height: 1000, requiredText: ["PR/CI", "PR and CI readiness", "Auto-merge dry-run"] },
  { name: "hermes-desktop", path: "/#/hermes", width: 1440, height: 1000, requiredText: ["Hermes", "Supervisor", "Cloud supervisor runbook"] },
  { name: "notifications-desktop", path: "/#/notifications", width: 1440, height: 1000, requiredText: ["Notifications", "Notification Matrix", "Bootstrap"] },
  { name: "overview-mobile", path: "/#/overview", width: 390, height: 900, requiredText: ["SkyBridge", "Daily operator picture"] },
  { name: "compact-embed", path: "/#/embed/compact", width: 420, height: 460, requiredText: ["Operator Status", "PR/CI", "Hermes"] }
];

const manifest = {
  schema_version: 1,
  generated_at: new Date().toISOString(),
  fixture_only: true,
  production_endpoint_used: false,
  data_source: "temporary SQLite database seeded by scripts/powershell/seed-demo-events.ps1",
  web_base_origin: webBaseUrl.origin,
  screenshots: viewports.map((viewport) => ({
    name: viewport.name,
    file: `${viewport.name}.png`,
    route: viewport.path,
    viewport: {
      width: viewport.width,
      height: viewport.height
    },
    required_text: viewport.requiredText
  }))
};

function fail(message) {
  throw new Error(`[browser-visual-qa] ${message}`);
}

function overlaps(a, b) {
  return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
}

async function assertNoPrimaryPanelOverlap(page) {
  const panels = await page.locator(".skybridge-panel, .skybridge-card, .skybridge-filterbar").evaluateAll((elements) =>
    elements.map((element) => {
      const rect = element.getBoundingClientRect();
      return {
        label: element.textContent?.trim().slice(0, 80) ?? "panel",
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height
      };
    })
  );

  for (let i = 0; i < panels.length; i += 1) {
    for (let j = i + 1; j < panels.length; j += 1) {
      const first = panels[i];
      const second = panels[j];
      if (first.width === 0 || first.height === 0 || second.width === 0 || second.height === 0) {
        fail(`zero-sized panel detected: "${first.label}" / "${second.label}"`);
      }
      if (overlaps(first, second)) {
        fail(`panel overlap detected: "${first.label}" overlaps "${second.label}"`);
      }
    }
  }
}

await mkdir(artifactDir, { recursive: true });

const browser = await chromium.launch();
const failures = [];

try {
  for (const viewport of viewports) {
    const context = await browser.newContext({
      viewport: { width: viewport.width, height: viewport.height },
      deviceScaleFactor: 1
    });
    const page = await context.newPage();
    const consoleErrors = [];
    page.on("console", (message) => {
      if (message.type() === "error") {
        consoleErrors.push(message.text());
      }
    });
    page.on("pageerror", (error) => {
      consoleErrors.push(error.message);
    });

    try {
      const target = new URL(viewport.path, webBase).toString();
      await page.goto(target, { waitUntil: "networkidle", timeout: 30_000 });
      await page.waitForSelector("body", { timeout: 10_000 });

      const text = await page.locator("body").innerText();
      if (text.trim().length < 80) {
        fail(`${viewport.name} appears blank or under-rendered`);
      }

      for (const required of viewport.requiredText) {
        if (!text.includes(required)) {
          fail(`${viewport.name} is missing required text: ${required}`);
        }
      }

      if (consoleErrors.length > 0) {
        fail(`${viewport.name} logged browser errors: ${consoleErrors.join(" | ")}`);
      }

      if (viewport.path === "/#/overview") {
        await assertNoPrimaryPanelOverlap(page);
      }

      await page.screenshot({
        path: path.join(artifactDir, `${viewport.name}.png`),
        fullPage: true
      });
    } catch (error) {
      failures.push(error instanceof Error ? error.message : String(error));
    } finally {
      await context.close();
    }
  }
} finally {
  await browser.close();
}

if (failures.length > 0) {
  fail(failures.join("\n"));
}

await writeFile(path.join(artifactDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);

console.log(`[browser-visual-qa] wrote ${viewports.length} screenshot(s) and manifest.json to ${artifactDir}`);
