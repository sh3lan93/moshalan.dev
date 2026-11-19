// Checks the JSON-LD in a built site. Usage: node tests/schema-check.mjs <outdir>
// Prints one line per problem; prints nothing when everything is fine.
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

const out = process.argv[2];
const PERSON = "https://moshalan.dev/#person";
const problems = [];

function graph(rel) {
  const html = readFileSync(join(out, rel), "utf8");
  const blocks = [...html.matchAll(/<script type="?application\/ld\+json"?>(.*?)<\/script>/gs)];
  if (blocks.length !== 1) {
    problems.push(`${rel}: expected 1 JSON-LD block, found ${blocks.length}`);
    return [];
  }
  try {
    return JSON.parse(blocks[0][1])["@graph"] ?? [];
  } catch (e) {
    problems.push(`${rel}: invalid JSON-LD (${e.message})`);
    return [];
  }
}
const types = (g) => g.map((n) => n["@type"]);
const expect = (rel, ok, what) => ok || problems.push(`${rel}: ${what}`);

// Home: WebSite + a full Person whose sameAs holds only profile URLs.
{
  const rel = "index.html", g = graph(rel);
  const person = g.find((n) => n["@type"] === "Person");
  expect(rel, types(g).includes("WebSite"), "no WebSite");
  expect(rel, !types(g).includes("Organization"), "site is typed Organization");
  expect(rel, person?.["@id"] === PERSON, "no Person with the shared @id");
  expect(rel, person?.sameAs?.length >= 2 && person.sameAs.every((u) => /^https:\/\/(www\.linkedin\.com|github\.com)\//.test(u)),
    "Person.sameAs must be profile URLs only");
  expect(rel, person?.jobTitle && person?.image, "Person lacks jobTitle or image");
}

// Profile pages.
for (const rel of ["about/index.html", "experience/index.html"]) {
  const g = graph(rel);
  expect(rel, types(g).includes("ProfilePage"), "not a ProfilePage");
  expect(rel, g.some((n) => n["@id"] === PERSON && n["@type"] === "Person"), "no Person");
}

// Work with me: one Service per data/services.yaml entry, provided by the Person.
{
  const rel = "work-with-me/index.html", g = graph(rel);
  const services = g.filter((n) => n["@type"] === "Service");
  const expected = (readFileSync(join(out, "..", "site", "data", "services.yaml"), "utf8").match(/^  - id:/gm) ?? []).length;
  expect(rel, services.length === expected && expected > 0, `expected ${expected} Service nodes, found ${services.length}`);
  expect(rel, services.every((s) => s.provider?.["@id"] === PERSON), "Service.provider is not the Person");
}

expect("projects/index.html", types(graph("projects/index.html")).includes("CollectionPage"), "not a CollectionPage");

// Posts: BlogPosting by the Person, with dates and an image; no page except posts is a BlogPosting.
const postsDir = join(out, "posts");
for (const slug of readdirSync(postsDir)) {
  const rel = join("posts", slug, "index.html");
  if (slug === "page" || !existsSync(join(out, rel))) continue;
  const g = graph(rel);
  const post = g.find((n) => n["@type"] === "BlogPosting");
  expect(rel, post, "no BlogPosting");
  expect(rel, post?.author?.["@id"] === PERSON, "author is not the Person");
  expect(rel, post?.datePublished && post?.dateModified && post?.image && post?.headline, "missing date, image or headline");
  expect(rel, types(g).includes("BreadcrumbList"), "no BreadcrumbList");
}
for (const rel of ["about/index.html", "experience/index.html", "work-with-me/index.html", "projects/index.html"]) {
  expect(rel, !types(graph(rel)).includes("BlogPosting"), "non-post page typed BlogPosting");
}

// The current employer is named on the Experience page only.
for (const rel of ["index.html", "work-with-me/index.html", "projects/index.html"]) {
  expect(rel, !JSON.stringify(graph(rel)).includes("worksFor"), "names the employer in JSON-LD");
}

if (problems.length) console.log([...new Set(problems)].join("\n"));
