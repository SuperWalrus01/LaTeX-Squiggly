// Home opens the strip of the home page's sections beside it, and it stays
// open, on every page, until Home is pressed again. Without this script Home
// is a plain link home.
const toggle = document.querySelector(".navhome-toggle");
const strip = document.getElementById("home-links");
if (toggle && strip) {
  const set = (open, animate) => {
    toggle.setAttribute("aria-expanded", String(open));
    strip.hidden = !open;
    strip.style.animation = animate ? "" : "none";
    try { localStorage.setItem("homeStripOpen", open ? "1" : "0"); } catch {}
  };
  let remembered = false;
  try { remembered = localStorage.getItem("homeStripOpen") === "1"; } catch {}
  set(remembered, false);
  toggle.addEventListener("click", (event) => {
    event.preventDefault();
    set(strip.hidden, true);
  });
}
