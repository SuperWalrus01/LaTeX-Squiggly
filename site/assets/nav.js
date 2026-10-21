// Home opens the strip of the home page's sections beside it. Without this
// script it is a plain link home.
const toggle = document.querySelector(".navhome-toggle");
const strip = document.getElementById("home-links");
if (toggle && strip) {
  const set = (open) => {
    toggle.setAttribute("aria-expanded", String(open));
    strip.hidden = !open;
  };
  toggle.addEventListener("click", (event) => {
    event.preventDefault();
    set(strip.hidden);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !strip.hidden) { set(false); toggle.focus(); }
  });
  strip.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => set(false)));
}
