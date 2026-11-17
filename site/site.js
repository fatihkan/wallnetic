// wallnetic.app: the demo desktop.
// - The desktop clock and the menu bar clock show the visitor's own time,
//   updated at each minute change, as Wallnetic's Desktop Clock does.
// - The wallpaper video plays only when Reduce Motion is off, and pauses while
//   it is off screen or the tab is hidden.
// - "Turn On Calm Mode" holds the motion, like the app's Calm Mode.
(function () {
  "use strict";

  // ---------- Clocks ----------
  var deskClock = document.querySelector("[data-clock]");
  var barClock = document.querySelector("[data-menubar-clock]");

  if (deskClock || barClock) {
    var time = document.createElement("span");
    var date = document.createElement("span");
    time.className = "time";
    date.className = "date";

    var renderClocks = function () {
      var now = new Date();
      var hm = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      if (deskClock) {
        time.textContent = hm;
        date.textContent = now.toLocaleDateString([], { weekday: "long", day: "numeric", month: "long" });
        if (!deskClock.firstChild) {
          deskClock.appendChild(time);
          deskClock.appendChild(date);
        }
      }
      if (barClock) {
        barClock.textContent =
          now.toLocaleDateString([], { weekday: "short", day: "numeric", month: "short" }) + "  " + hm;
      }
      setTimeout(renderClocks, 60000 - (now.getSeconds() * 1000 + now.getMilliseconds()) + 50);
    };

    renderClocks();
  }

  // ---------- Motion ----------
  var video = document.querySelector("video[data-motion]");
  var calm = document.querySelector("[data-calm]");
  if (!video) return;

  var reduce = window.matchMedia ? window.matchMedia("(prefers-reduced-motion: reduce)") : null;
  var calmOn = false;
  var visible = true;

  var stateLabel = document.querySelector("[data-state]");
  var pauseLabel = document.querySelector("[data-pause-label]");
  var calmLabel = document.querySelector("[data-calm-label]");

  var allowed = function () {
    return !(reduce && reduce.matches) && !calmOn && visible && !document.hidden;
  };

  var update = function () {
    if (allowed()) {
      var p = video.play();
      if (p && p.catch) p.catch(function () {});
    } else {
      video.pause();
    }
    var playing = allowed();
    if (stateLabel) stateLabel.textContent = playing ? "Playing" : (calmOn ? "Paused (Calm Mode)" : "Paused");
    if (pauseLabel) pauseLabel.textContent = playing ? "Pause" : "Play";
    if (calmLabel) calmLabel.textContent = calmOn ? "Turn Off Calm Mode" : "Turn On Calm Mode";
    if (calm) {
      // With Reduce Motion on, nothing moves, so there is nothing to calm.
      calm.hidden = !!(reduce && reduce.matches);
      calm.textContent = calmOn ? "Turn Off Calm Mode" : "Turn On Calm Mode";
      calm.setAttribute("aria-pressed", calmOn ? "true" : "false");
    }
  };

  if (calm) {
    calm.addEventListener("click", function () {
      calmOn = !calmOn;
      update();
    });
  }

  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      visible = entries[0].isIntersecting;
      update();
    }, { threshold: 0.15 }).observe(video);
  }

  document.addEventListener("visibilitychange", update);
  if (reduce && reduce.addEventListener) reduce.addEventListener("change", update);

  update();
})();
