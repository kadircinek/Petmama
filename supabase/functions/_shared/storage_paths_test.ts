// deno test supabase/functions/_shared/
import { chunk, collectStoragePaths, type ListedItem } from "./storage_paths.ts";

function assertEquals(actual: unknown, expected: unknown, msg = ""): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg} expected ${e}, got ${a}`);
}

Deno.test("collectStoragePaths walks folders and pages", async () => {
  const tree: Record<string, ListedItem[]> = {
    "u1": [
      { name: "a.jpg", id: "1" },
      { name: "b.jpg", id: "2" },
      { name: "sub", id: null },
      { name: "c.jpg", id: "3" },
    ],
    "u1/sub": [{ name: "d.jpg", id: "4" }],
  };
  const calls: string[] = [];
  const list = (prefix: string, limit: number, offset: number) => {
    calls.push(`${prefix}@${offset}`);
    return Promise.resolve((tree[prefix] ?? []).slice(offset, offset + limit));
  };
  const paths = await collectStoragePaths(list, "u1/", 2);
  assertEquals(paths.sort(), ["u1/a.jpg", "u1/b.jpg", "u1/c.jpg", "u1/sub/d.jpg"]);
  assertEquals(calls, ["u1@0", "u1@2", "u1/sub@0", "u1@4"]);
});

Deno.test("collectStoragePaths: empty folder", async () => {
  assertEquals(await collectStoragePaths(() => Promise.resolve([]), "nobody"), []);
});

Deno.test("chunk", () => {
  assertEquals(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assertEquals(chunk([], 3), []);
});
