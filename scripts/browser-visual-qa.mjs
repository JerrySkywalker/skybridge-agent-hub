import { mkdir } from "node:fs/promises";
import path from "node:path";

const webBase = process.env.SKYBRIDGE_VISUAL_QA_WEB_BASE ?? "http://127.0.0.1:3000";
const artifactDir = process.env.SKYBRIDGE_VISUAL_QA_ARTIFACT_DIR ?? ".agent/tmp/browser-visual-qa";

const { chromium } = await import("playwright");

const requiredConsoleText = [
  "Operator Console",
  "Metrics Summary",
  "Approval Queue",
  "Notifications",
  "Notification Matrix",
  "Run Detail"
];

const viewports = [
  { name: "operator-console-desktop", path: "/", width: 1440, height: 1000, requiredText: requiredConsoleText },
  { name: "operator-console-mobile", path: "/", width: 390, height: 900, requiredText: requiredConsoleText },
  { name: "compact-embed", path: "/#/embed/compact", width: 420, height: 420, requiredText: ["SkyBridge Health"] }
];

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

      if (viewport.path === "/") {
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

console.log(`[browser-visual-qa] wrote ${viewports.length} screenshot(s) to ${artifactDir}`);
