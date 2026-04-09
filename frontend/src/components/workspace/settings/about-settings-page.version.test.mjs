import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

void test("about settings page includes frontend and backend version sections", () => {
  const source = fs.readFileSync(
    path.resolve(process.cwd(), "src/components/workspace/settings/about-settings-page.tsx"),
    "utf8",
  );

  assert.match(source, /Frontend/i);
  assert.match(source, /Backend/i);
  assert.match(source, /build_time|Build Time/i);
  assert.match(source, /commit_message|Commit Message/i);
});

void test("about settings page fetches version info without new URL base construction", () => {
  const source = fs.readFileSync(
    path.resolve(process.cwd(), "src/components/workspace/settings/about-settings-page.tsx"),
    "utf8",
  );

  assert.doesNotMatch(source, /new URL\("\/api\/version",\s*getBackendBaseURL\(\)\)/);
  assert.match(source, /fetch\(`\$\{getBackendBaseURL\(\)\}\/api\/version`\)/);
});
