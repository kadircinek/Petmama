// Kullanıcının storage klasöründeki tüm dosya yollarını toplar (alt klasörler dahil).
// list fonksiyonu enjekte edilir → supabase-js olmadan test edilebilir.

/** supabase-js `storage.from(b).list(prefix, {limit, offset})` öğesinin ihtiyaç duyulan kısmı. */
export interface ListedItem {
  name: string;
  /** Klasörlerde null döner. */
  id: string | null;
}

export type ListFn = (prefix: string, limit: number, offset: number) => Promise<ListedItem[]>;

export async function collectStoragePaths(
  list: ListFn,
  prefix: string,
  pageSize = 100,
  maxDepth = 5,
): Promise<string[]> {
  const paths: string[] = [];
  const walk = async (dir: string, depth: number) => {
    for (let offset = 0;; offset += pageSize) {
      const items = await list(dir, pageSize, offset);
      for (const item of items) {
        const full = `${dir}/${item.name}`;
        if (item.id === null) {
          if (depth < maxDepth) await walk(full, depth + 1);
        } else {
          paths.push(full);
        }
      }
      if (items.length < pageSize) break;
    }
  };
  await walk(prefix.replace(/\/+$/, ""), 0);
  return paths;
}

export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
