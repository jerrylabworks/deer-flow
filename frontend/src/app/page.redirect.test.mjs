import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

void test("root page redirects directly to workspace", () => {
  const source = fs.readFileSync(
    path.resolve(process.cwd(), "src/app/page.tsx"),
    "utf8",
  );

  assert.match(source, /redirect\(\s*["']\/workspace["']\s*\)/);
});
