// The desktop clock on the wallpaper, as Wallnetic draws it: the visitor's
// own time and date, updated at each minute change, never announced.
(function () {
  var clock = document.querySelector("[data-clock]");
  if (!clock) return;
  var time = document.createElement("span");
  var date = document.createElement("span");
  time.className = "time";
  date.className = "date";

  function render() {
    var now = new Date();
    time.textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    date.textContent = now.toLocaleDateString([], { weekday: "long", day: "numeric", month: "long" });
    if (!clock.firstChild) {
      clock.appendChild(time);
      clock.appendChild(date);
    }
    setTimeout(render, 60000 - (now.getSeconds() * 1000 + now.getMilliseconds()) + 50);
  }

  render();
})();
