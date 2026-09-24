// The renderer's history: the LaTeX of the last 10 images copied or saved,
// newest first, each once. Only the source and a time are kept, never an
// image, so it stays a few kilobytes; the thumbnails are drawn again each time
// the list is opened. In chrome.storage.local rather than sync, whose 8 KB
// limit per item a long equation or two would reach.

const KEY = "rendererHistory";
export const LIMIT = 10;

export async function load() {
  try {
    const { [KEY]: list } = await chrome.storage.local.get(KEY);
    // Sliced too, so a list kept under a higher limit shows only the newest.
    return Array.isArray(list) ? list.filter((e) => typeof e?.source === "string").slice(0, LIMIT) : [];
  } catch {
    return [];
  }
}

const store = (list) => chrome.storage.local.set({ [KEY]: list }).catch(() => {});

export async function add(source) {
  if (source.trim() === "") return;
  const list = (await load()).filter((e) => e.source !== source);
  await store([{ source, time: Date.now() }, ...list].slice(0, LIMIT));
}

export async function remove(source) {
  await store((await load()).filter((e) => e.source !== source));
}

export async function clear() {
  await store([]);
}
