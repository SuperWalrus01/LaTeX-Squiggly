// Settings and site rules, shared by the page script, the popup and the
// options page. Stored in chrome.storage.sync, so they follow the user between
// their own Chrome profiles and go nowhere else.

(() => {
  const ns = (globalThis.LaTeXSquiggly ??= {});

  // Overleaf is the case the whole feature exists for: in a .tex source,
  // \alpha has to stay \alpha. The same list the desktop apps ship.
  const DEFAULT_SITES = [
    "cocalc.com",
    "latexbase.com",
    "overleaf.com",
    "papeeria.com",
    "sharelatex.com",
  ];

  const defaults = () => ({
    enabled: true,
    showNotices: true,
    excludedSites: [...DEFAULT_SITES],
  });

  // overleaf.com matches overleaf.com and www.overleaf.com, but not
  // notoverleaf.com and not overleaf.com.example.net.
  function hostMatches(host, pattern) {
    host = host.toLowerCase();
    pattern = pattern.toLowerCase();
    return host === pattern || host.endsWith("." + pattern);
  }

  // Accepts what a user is likely to paste, a full URL or a host with a www.
  // or a trailing slash, and returns the bare host, or null for a typo.
  function normalisedHost(input) {
    let text = input.trim().toLowerCase();
    if (text.length === 0) return null;
    if (/^[a-z][a-z0-9+.-]*:\/\//.test(text)) {
      try {
        text = new URL(text).hostname;
      } catch {
        return null;
      }
    } else {
      const slash = text.indexOf("/");
      if (slash >= 0) text = text.slice(0, slash);
    }
    if (text.startsWith("www.")) text = text.slice(4);
    if (!text.includes(".") || /\s/.test(text) || text.startsWith(".") || text.endsWith(".")) {
      return null;
    }
    return text;
  }

  // The rule that matches any of the hosts, or null. A page is checked along
  // with every frame it sits inside, so an editor embedded from an excluded
  // site stays excluded, and so does anything embedded in one.
  function matchingSite(hosts, excludedSites) {
    for (const host of hosts) {
      if (!host) continue;
      const site = excludedSites.find((pattern) => hostMatches(host, pattern));
      if (site) return site;
    }
    return null;
  }

  async function load() {
    // Sync storage can be unavailable, turned off by policy or over quota. The
    // defaults are the safe answer; without this the extension stayed off.
    let stored;
    try {
      stored = await chrome.storage.sync.get(defaults());
    } catch {
      return defaults();
    }
    return {
      enabled: stored.enabled !== false,
      showNotices: stored.showNotices !== false,
      excludedSites: Array.isArray(stored.excludedSites) ? stored.excludedSites : [...DEFAULT_SITES],
    };
  }

  const save = (changes) => chrome.storage.sync.set(changes);

  ns.settings = { DEFAULT_SITES, defaults, hostMatches, normalisedHost, matchingSite, load, save };
})();
