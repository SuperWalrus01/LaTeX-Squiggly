// The Home menu is a <details>, so it opens and closes without this script.
// This closes it the way a menu should: on a click elsewhere, on Escape, and
// once one of its links is chosen.
const menu = document.querySelector(".navmenu");
if (menu) {
  document.addEventListener("click", (event) => {
    if (menu.open && !menu.contains(event.target)) menu.open = false;
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && menu.open) {
      menu.open = false;
      menu.querySelector("summary").focus();
    }
  });
  menu.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => { menu.open = false; }));
}
