// Intent + reading analytics for PostHog. Loaded only when PostHog is configured
// (see layouts/_partials/extend_head.html). Pure functions are unit-tested in
// tests/analytics.test.mjs; keep them free of DOM access.
(function () {
  "use strict";

  var MARKS = [25, 50, 75, 100];
  var READ_SHARE = 0.4; // article_read needs 40% of the estimated reading time

  // Map a link to { cta, intent } or null when the link isn't tracked.
  // intent: "hiring" | "consulting" | "other".
  function classify(href, pagePath, origin) {
    if (!href) return null;
    if (/^mailto:/i.test(href)) {
      return { cta: "email", intent: /^\/work-with-me\/?$/.test(pagePath) ? "consulting" : "other" };
    }
    var u;
    try { u = new URL(href, origin); } catch (e) { return null; }
    var host = u.hostname.replace(/^www\./, "");
    var path = u.pathname;
    if (u.origin === origin) {
      if (/^\/resume\.pdf$/.test(path)) return { cta: "resume", intent: "hiring" };
      if (/^\/experience\/?$/.test(path)) return { cta: "experience", intent: "hiring" };
      if (/^\/work-with-me\/?$/.test(path)) return { cta: "work_with_me", intent: "consulting" };
      if (/^\/projects\/?$/.test(path)) return { cta: "projects", intent: "other" };
      return null;
    }
    if (host === "linkedin.com" && /^\/in\//.test(path)) return { cta: "linkedin", intent: "hiring" };
    if (host === "cal.com") return { cta: "calcom", intent: "consulting" };
    if (host === "github.com") return { cta: "github", intent: "other" };
    return null;
  }

  // Milestones newly passed at `percent`, given the ones already sent.
  function crossedMarks(percent, sent) {
    return MARKS.filter(function (m) { return percent >= m && !sent.has(m); });
  }

  // Read to the end = reached the end AND stayed 40% of the reading time.
  function isRead(reachedEnd, seconds, readingMinutes) {
    return !!reachedEnd && seconds >= readingMinutes * 60 * READ_SHARE;
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { classify: classify, crossedMarks: crossedMarks, isRead: isRead };
    return;
  }

  // ---------- browser wiring ----------
  function ph() { return window.posthog; }

  function locate(el) {
    var rules = [
      ["[data-door]", "home_doors"], [".brand-hero", "hero"], ["#menu", "nav"],
      [".social-icons", "social_icons"], [".brand-contact", "contact"], [".brand-proof", "proof"],
      [".brand-cards", "services"], [".brand-timeline", "experience"], [".post-content", "article_body"],
      [".footer", "footer"]
    ];
    for (var i = 0; i < rules.length; i++) if (el.closest(rules[i][0])) return rules[i][1];
    return "page";
  }

  document.addEventListener("click", function (ev) {
    var a = ev.target.closest && ev.target.closest("a[href]");
    if (!a || !ph()) return;
    var hit = classify(a.getAttribute("href"), location.pathname, location.origin);
    if (!hit) return;
    // sendBeacon survives the page unloading when the link navigates in this tab
    ph().capture("cta_clicked", {
      cta: hit.cta, intent: hit.intent, location: locate(a),
      link_url: a.href, link_text: (a.textContent || "").trim().slice(0, 80)
    }, { transport: "sendBeacon" });
  }, true);

  var metaEl = document.getElementById("article-meta");
  if (!metaEl) return;
  var meta;
  try { meta = JSON.parse(metaEl.textContent); } catch (e) { return; }

  var sent = new Set(), seconds = 0, reachedEnd = false, readSent = false;
  function props(extra) {
    var p = { article_path: meta.path, title: meta.title, reading_time_min: meta.readingTime };
    for (var k in extra) p[k] = extra[k];
    return p;
  }
  function checkRead() {
    if (!readSent && isRead(reachedEnd, seconds, meta.readingTime) && ph()) {
      readSent = true;
      ph().capture("article_read", props({ seconds: seconds }));
    }
  }
  function onScroll() {
    var body = document.querySelector(".post-content");
    if (!body || !ph()) return;
    var r = body.getBoundingClientRect();
    var pct = r.height ? Math.min(100, Math.max(0, (window.innerHeight - r.top) / r.height * 100)) : 100;
    crossedMarks(pct, sent).forEach(function (m) {
      sent.add(m);
      ph().capture("article_progress", props({ percent: m, seconds: seconds }));
    });
    if (pct >= 100) { reachedEnd = true; checkRead(); }
  }
  // throttle with a timer, not requestAnimationFrame: frames can be paused, and a paused
  // frame would leave the throttle stuck and silence the rest of the visit
  var pending = false;
  window.addEventListener("scroll", function () {
    if (pending) return;
    pending = true;
    setTimeout(function () { pending = false; onScroll(); }, 200);
  }, { passive: true });
  // count only time the tab is visible
  setInterval(function () {
    if (document.visibilityState === "visible") { seconds++; checkRead(); }
  }, 1000);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", onScroll);
  else onScroll();
})();
