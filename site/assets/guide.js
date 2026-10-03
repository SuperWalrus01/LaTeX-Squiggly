// The guide's video carousels: one large video at a time. The track scrolls
// sideways and snaps, so swiping works without this script; the script adds
// the buttons, the tabs, the arrow keys, links straight to one video
// (#watch-...), and pausing a video once it is moved away from.
for (const carousel of document.querySelectorAll("[data-carousel]")) {
  const track = carousel.querySelector(".carousel-track");
  const slides = [...track.querySelectorAll(".slide")];
  const tabs = [...carousel.querySelectorAll(".carousel-tabs button")];
  const [prev, next] = carousel.querySelectorAll(".carousel-step");
  let current = 0;

  const show = (i) => {
    if (i !== current) slides[current].querySelector("video")?.pause();
    current = i;
    tabs.forEach((tab, k) => tab.setAttribute("aria-current", String(k === i)));
    // Keep the current tab fully in view in its strip.
    const strip = tabs[i].closest("ol"), tab = tabs[i].getBoundingClientRect(), box = strip.getBoundingClientRect();
    if (tab.left < box.left) strip.scrollBy({ left: tab.left - box.left - 8, behavior: "smooth" });
    else if (tab.right > box.right) strip.scrollBy({ left: tab.right - box.right + 8, behavior: "smooth" });
    prev.disabled = i === 0;
    next.disabled = i === slides.length - 1;
  };
  const go = (i, smooth = true) => {
    i = Math.max(0, Math.min(slides.length - 1, i));
    track.scrollTo({ left: i * track.clientWidth, behavior: smooth ? "smooth" : "auto" });
    show(i);
  };

  prev.addEventListener("click", () => go(current - 1));
  next.addEventListener("click", () => go(current + 1));
  tabs.forEach((tab, k) => tab.addEventListener("click", () => go(k)));
  track.addEventListener("keydown", (event) => {
    if (event.key === "ArrowRight") { event.preventDefault(); go(current + 1); }
    if (event.key === "ArrowLeft") { event.preventDefault(); go(current - 1); }
  });
  // Swiping: the slide most in view becomes the current one.
  let settle = 0;
  track.addEventListener("scroll", () => {
    clearTimeout(settle);
    settle = setTimeout(() => {
      const i = Math.round(track.scrollLeft / track.clientWidth);
      if (i !== current) show(i);
    }, 90);
  });
  carousel.goTo = (id) => {
    const i = slides.findIndex((slide) => slide.id === id);
    if (i < 0) return false;
    go(i, false);
    carousel.scrollIntoView({ block: "start" });
    return true;
  };
  show(0);
}

// A link to one video, from the index at the top, shows that slide.
function followHash() {
  const id = decodeURIComponent(location.hash.slice(1));
  if (!id.startsWith("watch-")) return;
  for (const carousel of document.querySelectorAll("[data-carousel]")) if (carousel.goTo(id)) return;
}
window.addEventListener("hashchange", followHash);
followHash();
