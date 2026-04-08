import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

void test("new thread stream keeps threadId undefined until server creates it", () => {
  const source = fs.readFileSync(
    path.resolve(process.cwd(), "src/core/threads/hooks.ts"),
    "utf8",
  );

  assert.match(
    source,
    /const \[onStreamThreadId, setOnStreamThreadId\] = useState\([\s\S]*threadId \?\? undefined[\s\S]*\)/,
  );
  assert.match(source, /threadId:\s+effectiveThreadId/);
  assert.match(source, /thread_id:\s+effectiveThreadId/);
});
