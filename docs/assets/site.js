// Shared behaviour for every language version of the landing page.
// Each page sets window.SITE with its own strings before loading this file.
(function () {
  var T = window.SITE;
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var PAUSE_ICON = '<svg viewBox="0 0 10 10" aria-hidden="true"><rect x="1" y="0.5" width="2.6" height="9" rx="0.6" fill="currentColor"/><rect x="6.4" y="0.5" width="2.6" height="9" rx="0.6" fill="currentColor"/></svg>';
  var PLAY_ICON = '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M2 0.8v8.4L9.2 5z" fill="currentColor"/></svg>';

  function $(id) { return document.getElementById(id); }

  function fill(template, values) {
    return template.replace(/\{(\w+)\}/g, function (_, key) { return values[key]; });
  }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  // Remember a language picked with the switch, so the English page stops redirecting.
  Array.prototype.forEach.call(document.querySelectorAll(".lang a"), function (a) {
    a.addEventListener("click", function () {
      try { localStorage.setItem("lang", a.getAttribute("hreflang").toLowerCase()); } catch (e) {}
    });
  });

  // Poem carousel
  (function () {
    var poems = T.poems;
    var hanStack = $("d-han"), enStack = $("d-en");
    if (!hanStack || !poems) return;

    // The first poem is in the HTML for search engines; build the rest.
    poems.slice(1).forEach(function (p) {
      var h = el("div");
      h.appendChild(el("p", "d-title", p.t));
      h.appendChild(el("p", "d-author", p.a));
      var lines = el("p", "d-lines");
      p.l.forEach(function (line, i) {
        if (i) lines.appendChild(document.createElement("br"));
        lines.appendChild(document.createTextNode(line));
      });
      h.appendChild(lines);
      hanStack.appendChild(h);

      var e = el("div");
      if (p.et) e.appendChild(el("h3", "", p.et));
      e.appendChild(el("p", "by", p.by));
      e.appendChild(el("p", "trans", p.tr));
      e.appendChild(el("p", "note", p.n));
      enStack.appendChild(e);
    });

    var slides = [hanStack.children, enStack.children];
    var count = poems.length, index = 0, paused = false, hover = false, visible = true, timer = null;
    var DELAY = 9000, SHIFT = 40;
    var dotsBox = $("d-dots"), pauseBtn = $("d-pause"), card = $("daily-card");

    var dots = poems.map(function (p, i) {
      var b = el("button", "dot");
      b.type = "button";
      b.setAttribute("aria-label", fill(T.poemDot, { n: i + 1, title: p.et || p.t }));
      b.addEventListener("click", function () { show(i, i > index ? 1 : -1, true); });
      dotsBox.appendChild(b);
      return b;
    });

    // Slide the new poem in from one side while the old one leaves the other way.
    function show(i, dir, fromUser) {
      i = (i + count) % count;
      slides.forEach(function (list) {
        Array.prototype.forEach.call(list, function (slide, k) {
          if (k === i) {
            if (!reduce && dir && k !== index) {
              slide.style.transition = "none";
              slide.style.transform = "translateX(" + dir * SHIFT + "px)";
              void slide.offsetWidth;
              slide.style.transition = "";
            }
            slide.classList.remove("off");
            slide.style.transform = "";
            slide.removeAttribute("aria-hidden");
          } else {
            if (k === index && dir && !reduce) slide.style.transform = "translateX(" + -dir * SHIFT + "px)";
            slide.classList.add("off");
            slide.setAttribute("aria-hidden", "true");
          }
        });
      });
      index = i;
      dots.forEach(function (d, k) { d.setAttribute("aria-current", k === i ? "true" : "false"); });
      enStack.setAttribute("aria-live", fromUser ? "polite" : "off");
      schedule();
    }

    function schedule() {
      clearTimeout(timer);
      if (!paused && !hover && visible) timer = setTimeout(function () { show(index + 1, 1); }, DELAY);
    }

    function setPaused(value) {
      paused = value;
      pauseBtn.setAttribute("aria-label", paused ? T.playPoems : T.pausePoems);
      pauseBtn.innerHTML = paused ? PLAY_ICON : PAUSE_ICON;
      schedule();
    }

    $("d-prev").addEventListener("click", function () { show(index - 1, -1, true); });
    $("d-next").addEventListener("click", function () { show(index + 1, 1, true); });
    pauseBtn.addEventListener("click", function () { setPaused(!paused); });

    // Hold still while someone is reading or using the controls.
    card.addEventListener("mouseenter", function () { hover = true; schedule(); });
    card.addEventListener("mouseleave", function () { hover = false; schedule(); });
    card.addEventListener("focusin", function () { hover = true; schedule(); });
    card.addEventListener("focusout", function (e) {
      if (!card.contains(e.relatedTarget)) { hover = false; schedule(); }
    });
    card.addEventListener("keydown", function (e) {
      if (e.key === "ArrowLeft") show(index - 1, -1, true);
      else if (e.key === "ArrowRight") show(index + 1, 1, true);
    });

    // Swipe on touch screens.
    var startX = null, startY = 0;
    card.addEventListener("touchstart", function (e) {
      startX = e.touches[0].clientX; startY = e.touches[0].clientY;
    }, { passive: true });
    card.addEventListener("touchend", function (e) {
      if (startX === null) return;
      var dx = e.changedTouches[0].clientX - startX, dy = e.changedTouches[0].clientY - startY;
      startX = null;
      if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) {
        if (dx < 0) show(index + 1, 1, true); else show(index - 1, -1, true);
      }
    }, { passive: true });

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        visible = entries[0].isIntersecting;
        schedule();
      }, { threshold: 0.3 }).observe(card);
    }
    document.addEventListener("visibilitychange", function () {
      visible = !document.hidden;
      schedule();
    });

    // Start on the same poem for everyone on a given day, like the app's Poem of the Day.
    var start = new Date(new Date().getFullYear(), 0, 0);
    var day = Math.floor((new Date() - start) / 86400000);
    index = day % count;
    show(index, 0);
    if (reduce) setPaused(true);
  })();

  // Personal seal: step through a few sample names until the reader picks one.
  (function () {
    var stage = $("seal-stage");
    if (!stage) return;
    var names = T.seals;
    var imgs = stage.querySelectorAll(".seal-imgs img");
    var chips = stage.querySelectorAll(".seal-chip");
    var en = $("seal-en"), zh = $("seal-zh"), py = $("seal-py");
    var index = 0, timer = null;

    function show(i) {
      index = i;
      Array.prototype.forEach.call(imgs, function (img, k) { img.classList.toggle("off", k !== i); });
      Array.prototype.forEach.call(chips, function (c, k) { c.setAttribute("aria-pressed", k === i ? "true" : "false"); });
      en.textContent = names[i][0]; zh.textContent = names[i][1]; py.textContent = names[i][2];
    }

    Array.prototype.forEach.call(chips, function (chip, k) {
      chip.addEventListener("click", function () { clearInterval(timer); timer = null; show(k); });
    });

    if (!reduce && "IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        if (entries[0].isIntersecting && timer === null && !stage.dataset.picked) {
          timer = setInterval(function () { show((index + 1) % names.length); }, 3200);
        } else if (!entries[0].isIntersecting && timer !== null) {
          clearInterval(timer); timer = null;
        }
      }, { threshold: 0.4 }).observe(stage);
    }
    stage.addEventListener("click", function (e) {
      if (e.target.closest(".seal-chip")) stage.dataset.picked = "1";
    });
  })();

  // Hero demo: cycle through the screen recordings inside the phone.
  (function () {
    var screen = $("demo-screen");
    if (!screen) return;
    var videos = Array.prototype.slice.call(screen.querySelectorAll("video"));
    var steps = T.steps;
    var label = $("demo-label");
    var text = $("demo-text");
    var nav = $("demo-nav");
    var pauseBtn = $("demo-pause");
    var current = -1, paused = reduce, visible = true;

    var dots = steps.map(function (step, i) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "dot";
      b.setAttribute("aria-label", fill(T.showStep, { step: step[0] }));
      b.addEventListener("click", function () { go(i, true); });
      nav.insertBefore(b, pauseBtn);
      return b;
    });

    function load(v) {
      if (!v.getAttribute("src")) { v.src = v.dataset.src; v.preload = "auto"; }
    }

    function play(v) {
      var p = v.play();
      if (p && p.catch) p.catch(function () {});
    }

    function go(i, fromUser) {
      var prev = videos[current];
      current = i;
      var v = videos[i];
      load(v);
      load(videos[(i + 1) % videos.length]);
      videos.forEach(function (x, k) { x.classList.toggle("on", k === i); });
      dots.forEach(function (d, k) { d.setAttribute("aria-current", k === i ? "true" : "false"); });
      label.textContent = steps[i][0];
      text.textContent = steps[i][1];
      if (prev && prev !== v) { setTimeout(function () { prev.pause(); }, 450); }
      v.currentTime = 0;
      if (!paused || fromUser) { if (visible) play(v); }
    }

    videos.forEach(function (v, i) {
      v.addEventListener("ended", function () {
        if (i === current && !paused) go((i + 1) % videos.length);
      });
    });

    function setPaused(value) {
      paused = value;
      pauseBtn.setAttribute("aria-label", paused ? T.playDemo : T.pauseDemo);
      pauseBtn.innerHTML = paused ? PLAY_ICON : PAUSE_ICON;
      var v = videos[current];
      if (paused) v.pause(); else if (visible) play(v);
    }
    pauseBtn.addEventListener("click", function () { setPaused(!paused); });

    // Only spend bandwidth and battery while the phone is on screen.
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        visible = entries[0].isIntersecting;
        var v = videos[current];
        if (!v) return;
        if (visible && !paused) play(v); else v.pause();
      }, { threshold: 0.25 }).observe(screen);
    }

    go(0);
    if (reduce) setPaused(true);
  })();
})();
