import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

void test("chat page uses router.replace when a new thread is created", () => {
  const source = fs.readFileSync(
    path.resolve(process.cwd(), "src/app/workspace/chats/[thread_id]/page.tsx"),
    "utf8",
  );

  assert.match(source, /router\.replace\(`\/workspace\/chats\/\$\{createdThreadId\}`\)/);
  assert.doesNotMatch(source, /history\.replaceState\(null,\s*"",\s*`\/workspace\/chats\/\$\{createdThreadId\}`\)/);
});
