// Unit tests for the pure decision functions in assets/js/analytics.js.
// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { classify, crossedMarks, isRead } = require("../assets/js/analytics.js");

const ORIGIN = "https://moshalan.dev";
const c = (href, page = "/") => classify(href, page, ORIGIN);

test("hiring links", () => {
  assert.deepEqual(c("/resume.pdf"), { cta: "resume", intent: "hiring" });
  assert.deepEqual(c("https://moshalan.dev/resume.pdf"), { cta: "resume", intent: "hiring" });
  assert.deepEqual(c("https://www.linkedin.com/in/mohamedsh3lan93/"), { cta: "linkedin", intent: "hiring" });
  assert.deepEqual(c("/experience/"), { cta: "experience", intent: "hiring" });
});

test("consulting links", () => {
  assert.deepEqual(c("/work-with-me/"), { cta: "work_with_me", intent: "consulting" });
  assert.deepEqual(c("https://moshalan.dev/work-with-me/"), { cta: "work_with_me", intent: "consulting" });
  assert.deepEqual(c("https://cal.com/mohamed-shalan-gwjgvq/15min"), { cta: "calcom", intent: "consulting" });
});

test("email counts as consulting only on Work with me", () => {
  assert.deepEqual(c("mailto:mohamed.sh3lan.93@gmail.com", "/work-with-me/"), { cta: "email", intent: "consulting" });
  assert.deepEqual(c("mailto:mohamed.sh3lan.93@gmail.com", "/"), { cta: "email", intent: "other" });
});

test("other tracked links", () => {
  assert.deepEqual(c("https://github.com/sh3lan93"), { cta: "github", intent: "other" });
  assert.deepEqual(c("https://github.com/sh3lan93/mobile-automator"), { cta: "github", intent: "other" });
  assert.deepEqual(c("/projects/"), { cta: "projects", intent: "other" });
});

test("untracked links return null", () => {
  assert.equal(c("/posts/some-post/"), null);
  assert.equal(c("#top"), null);
  assert.equal(c(""), null);
  assert.equal(c("https://example.com/"), null);
  // a look-alike host is not LinkedIn / Cal.com
  assert.equal(c("https://linkedin.com.evil.test/"), null);
  // PaperMod's "share on LinkedIn" button is a reader sharing, not a hiring signal
  assert.equal(c("https://www.linkedin.com/shareArticle?mini=true&url=https://moshalan.dev/posts/x/"), null);
});

test("crossedMarks reports each milestone once", () => {
  assert.deepEqual(crossedMarks(10, new Set()), []);
  assert.deepEqual(crossedMarks(55, new Set()), [25, 50]);
  assert.deepEqual(crossedMarks(55, new Set([25, 50])), []);
  assert.deepEqual(crossedMarks(100, new Set([25, 50])), [75, 100]);
});

test("isRead needs the end plus 40% of reading time", () => {
  assert.equal(isRead(true, 48, 2), true);   // 40% of 120s = 48s
  assert.equal(isRead(true, 47, 2), false);  // too fast: skimmed
  assert.equal(isRead(false, 999, 2), false); // never reached the end
  assert.equal(isRead(true, 0, 0), true);    // no reading time known
});
