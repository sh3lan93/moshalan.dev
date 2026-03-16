---
title: "I Built My Own AI News Feed Because I Kept Missing What Mattered"
date: 2026-03-16T00:00:00+04:00
draft: false
description: "A fully local AI dashboard built with n8n, Ollama, and SQLite — the honest story of building it, debugging it, and what I learned about information overload."
tags: [AI, LLM, Ollama, n8n, Productivity, Side Project]
categories: [Engineering]
featuredImage: "/images/ai-pulse.webp"
featuredImagePreview: "/images/ai-pulse.webp"
---

I spent an hour every morning trying to keep up with AI tooling — and I was still behind.

Not behind in the casual, "oh I haven't read that yet" sense. Behind in the way that matters at work. A colleague would mention an MCP update that shipped last week and I'd nod along, quietly Googling it under the table. Someone would demo a workflow pattern I should have known about, and I'd realize I'd scrolled past the announcement three days ago without registering it.

My morning routine looked productive on the surface: Twitter, Reddit, three newsletters, a manual sweep of GitHub releases. Seventy minutes of "staying current." But here's what I was actually doing — I was letting five different algorithms decide what mattered to me, then hoping the important stuff would float up. It didn't. The algorithm optimizes for engagement, not relevance to my specific work.

I'm a Senior Software Engineer who works heavily with AI tooling agents, context engineering, MCP integrations, workflow automation. That's a specific enough niche that no general-purpose aggregator will ever serve it well. Feedly doesn't know I care about prompt patterns but not benchmark-only announcements. Pocket doesn't know the difference between an MCP protocol update (drop everything) and a GPT-5 rumor roundup (ignore completely).

So I stopped reading and started building.

![AI Pulse Dashboard showing the personalized feed with AI-scored and summarized articles](/images/ai-pulse/ai-pulse-dashboard.webp)

## What AI Pulse Actually Does

The concept is simple: a pipeline that wakes up before I do, reads everything, scores it against my specific interests using local LLMs, and hands me 15–20 articles instead of 300.

Every morning at 6 AM, an automated workflow pulls articles from 47+ sources — RSS feeds from tech blogs (Anthropic, OpenAI, Simon Willison, Hugging Face), Reddit communities (r/MachineLearning, r/LocalLLaMA), GitHub release feeds, and trending repos. Everything gets deduplicated via a SHA-256 hash of the URL and stored in a local SQLite database. By 6:30 AM, there are roughly 200–400 raw articles waiting.

At 7 AM, a second workflow sends each unscored article through **Mistral 7B** — a fast, lightweight language model running locally on my Mac. The prompt is tuned to my interests: AI dev tools, agentic workflows, model releases, SDLC automation, context engineering. Mistral returns a relevance score from 0 to 100 and a category. This takes about 5–15 seconds per article with GPU acceleration.

![n8n workflow for AI Pulse two-pass article scoring with Mistral 7B](/images/ai-pulse/ai-pulse-n8n-workflow-scoring.webp)

![JSON response from Ollama's Mistral 7B with relevance score and category for AI Pulse scoring](/images/ai-pulse/ai-puls-n8n-workflow-scoring-response.webp)



Articles scoring 60 or higher get promoted to a deeper pass. **Llama 3 8B** — a larger, more capable model — reads them again and generates a 2–3 sentence summary, an importance rating (1–5 stars), a "why it matters to you" sentence, and auto-tags. The "why it matters" field is what I look at first on the dashboard. It answers "should I read this right now?" in a single sentence, and when it works well, it's surprisingly good at making that call.

![AI Pulse dashboard article card showing AI-generated summary, importance rating, and why-it-matters sentence](/images/ai-pulse/ai-pulse-dashboard-article-card.webp)

On Sundays, the system collects the week's top-rated articles and identifies 3–5 emerging patterns — themes that only become visible when you step back from individual articles. Reading the weekly trend report takes two minutes and gives me pattern recognition I'd never get from daily scrolling.

![AI Pulse weekly trends report identifying 3–5 emerging patterns from the week's top-rated articles](/images/ai-pulse/ai-puls-dashboard-weekly-trends.webp)

The result: I open a dashboard with my morning coffee, scan the enriched feed, and I'm caught up in 10 minutes. No algorithm. No ads. No infinite scroll.

![AI Pulse Architecture](/images/ai-pulse/ai-pulse-architecture.png)

## The Stack: Everything Local, Everything Free

The whole thing runs on my Mac (M3 chip, 18 GB unified memory). No cloud APIs, no subscriptions, no one else's servers.

**[n8n](https://n8n.io)** handles orchestration — it's a self-hosted workflow automation tool running in Docker that lets me build the entire ingest-score-enrich pipeline visually with cron scheduling. **[Ollama](https://ollama.ai)** runs the LLMs natively on macOS with Metal GPU acceleration (more on why "natively" matters in a minute). **SQLite** stores everything — articles, scores, summaries, calibration data — in a single portable file using WAL mode, which allows concurrent reads and writes without locking issues. **Express.js** with **better-sqlite3** serves the API. **Vue 3** with Tailwind CSS powers the dashboard.

Running cost: $0/month. Privacy surface: zero. Everything stays on my machine.

## The Messy Middle: Where Things Actually Got Interesting

The architecture diagram is clean. The reality of building it was not. These are the problems that consumed actual hours — the kind that don't show up in README files.

![n8n ingestion workflow pulling articles from 47+ RSS feeds, Reddit, and GitHub releases into SQLite](/images/ai-pulse/ai-puls-ingestion-workflow.webp)

### Docker on Mac Can't See Your GPU

This one burned an entire evening. I had Ollama running inside a Docker container alongside n8n, and scoring was taking 45–60 seconds per article. I assumed this was just what local inference felt like on a laptop.

It's not. Docker on macOS runs through a Linux virtual machine (whether you use Colima or Docker Desktop), and that VM has zero access to Apple Silicon's Metal GPU. Ollama was doing CPU-only inference without telling me.

**The Fix:** Run Ollama **natively** on macOS, outside Docker, and have the containerized n8n workflows reach it via `host.docker.internal:11434`. Inference dropped from 45 seconds to 5–15 seconds. Same hardware, same model, 4x faster — just because of where the process runs.

If you're running any ML workload on an Apple Silicon Mac through Docker, check whether you're actually using your GPU. You probably aren't.

### n8n's Python Support Will Test Your Patience

n8n is a powerful orchestration tool, but its Python execution story in v2 is rough. The default Docker image is distroless — no `apk`, no `apt-get`, no package manager at all. Python runs in a separate "task runner" sidecar container (`n8nio/runners`), and that sandbox blocks all standard library imports by default.

The documentation says you can fix this with an environment variable. That environment variable has a known bug and gets ignored.

**The Fix:** Create a custom JSON config file and mount it at `/etc/n8n-task-runners.json` inside the container.

And the sandbox itself has quirks: `_input.all()` doesn't exist despite appearing in examples, `type()` is blocked, and items arrive wrapped in a `{'json': {...}}` dictionary you have to unwrap manually. None of this is documented clearly. I pieced it together from GitHub issues.

### Type Safety in Unexpected Places

n8n's HTTP Request node has a "Using Fields" mode where you fill in key-value pairs for the request body. Convenient — until you realize it sends boolean `false` as the string `"false"`. Ollama's API is written in Go and is strict about types. It rejects the request silently.

**The Fix:** Build the entire JSON body in a Python Code node using `json.dumps()` and send it through the HTTP node's "Raw" body mode. Learned this after an afternoon of debugging responses that looked correct in the n8n UI but weren't.

### Model Memory Management Is Real

On 18 GB of unified memory, you can't have two 5–6 GB models loaded simultaneously without macOS swapping to disk and everything grinding to a halt. By default, Ollama keeps a loaded model in VRAM for 5 minutes after the last request. If Pass 2 (Llama 3 8B) starts while Mistral 7B from Pass 1 is still resident, both models eat ~11 GB together — leaving almost nothing for the OS, Docker, and n8n.

**The Fix:** After the Pass 1 scoring loop finishes, send a `POST /api/generate` request with `keep_alive: 0` to force-evict Mistral before loading Llama 3. Two lines of config that prevent hours of debugging mystery slowdowns where everything technically works but takes 10x longer.

![Timeline chart showing Mistral 7B being evicted from memory before Llama 3 8B loads during AI Pulse's two-pass scoring pipeline](/images/ai-pulse/ai-pulse-models-loading-timeline.webp)

### Tailwind v4 and better-sqlite3

Two quick dependency traps. Running `npm install tailwindcss` now pulls v4 by default, which has a completely different configuration format from v3. If you're following any tutorial written before 2025, pin it: `npm install tailwindcss@3`. And `better-sqlite3` v9 has no prebuilt binary for Node 25 on ARM64 — use v12 (`npm install better-sqlite3@^12.6.2`). Each of these cost me about an hour of confusion.

## What I'd Do Differently

- **Start with the schema, not the ingestion.** I built the data pipeline first because it felt like the "foundation." But every decision downstream — what the API returns, how the dashboard filters, what the calibration system stores — depends on the database schema. I should have designed those tables on paper before writing a single workflow. It would have saved two refactors.

- **Test prompts in isolation before wiring them into workflows.** I spent significant time debugging n8n issues that turned out to be prompt quality problems, and vice versa. Running the scoring prompt directly via `curl` against the Ollama API before connecting it to n8n makes the boundary between "my prompt is bad" and "my workflow is broken" much clearer.

- **Enable WAL mode from day one.** SQLite's default journal mode doesn't handle concurrent writes well. I added `PRAGMA journal_mode=WAL` after hitting deadlocks from n8n's parallel ingestion branches. It should have been the first line in my schema migration.

## The Part I'm Most Excited About

The feature that makes AI Pulse more than a filtered RSS reader is the calibration loop — and it's only half-built.

Every time I rate an article on the dashboard, the system stores a calibration record: the AI's score, my score, the gap between them, and the article summary. Over time, this builds a library of examples showing exactly where the AI's taste diverges from mine.

The plan is to inject the most informative examples as few-shot context into every scoring prompt. So if I've consistently rated speculation articles low and prompt engineering articles high, the model sees that pattern before it scores the next batch:

> "GPT-5 rumors and speculation roundup" → AI: 80, Me: 25 (I prefer confirmed news, not speculation)
>
> "How to structure system prompts for reliable JSON output" → AI: 55, Me: 90 (Prompt patterns are core to my work — AI undervalued this)

Every 50 ratings, a workflow synthesizes all calibration data into a natural-language preference profile that gets prepended to every future prompt. The convergence chart in the dashboard will show whether the AI's scores gradually align with mine over weeks of consistent rating.

The infrastructure is there — the calibration API, the ratings UI, the stats dashboard. The n8n workflow side (few-shot injection and auto-profile generation) is the remaining work. Whether the scores actually converge is an experiment I'm running on myself.

![AI Pulse calibration dashboard showing divergence between AI scores and user ratings over time](/images/ai-pulse/ai-pulse-calibration-view.webp)

## What's Next

The project is genuinely useful today. I use it every morning and I'm consistently finding things I would have missed. The backlog:

- Wire the few-shot calibration into the scoring prompts and build auto-profile generation
- Tune relevance thresholds using real data (2,470 articles ingested so far, 89 promoted and deeply analyzed)

- Possibly add YouTube channel tracking via RSS and Twitter/X via RSSHub

## The Real Takeaway

The most useful thing I got from this project isn't the dashboard. It's the act of writing the scoring prompt.

When you have to describe your interests precisely enough for an LLM to score against them, you're forced to answer a question most of us skip: *what do I actually care about?* Not what's trending, not what gets engagement, not what everyone else is reading — what matters to my specific work, right now.

I expected to build a tool that filters articles. What I actually built was a mirror that reflects my professional priorities back at me, then asks whether the AI agrees. Sometimes it doesn't. And figuring out why is the most interesting part.

---

*AI Pulse runs entirely on a Mac with 18 GB RAM. The full stack — n8n, Ollama (Mistral 7B + Llama 3 8B), SQLite, Express.js, Vue 3, Tailwind CSS — costs $0/month to operate.*
