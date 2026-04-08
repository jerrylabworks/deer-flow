import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

void test("message list item does not read thread id directly from route params", () => {
  const source = fs.readFileSync(
    path.resolve(process.cwd(), "src/components/workspace/messages/message-list-item.tsx"),
    "utf8",
  );

  assert.doesNotMatch(source, /useParams<\{\s*thread_id:\s*string\s*\}>\(/);
});
