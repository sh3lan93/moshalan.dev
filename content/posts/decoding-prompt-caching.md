---
title: "Decoding Prompt Caching"
date: 2026-11-04T12:00:00+04:00
draft: false
author: "Mohamed Shalan"
description: "Why a Claude Code session can suddenly get slower and more expensive: how prompt caching works, what breaks the cache, and the habits that keep it warm."
tags: [AI, Claude Code, AI Agents, Prompt Caching]
categories: [AI]
cover:
  image: "images/decoding-prompt-caching.webp"
  alt: "Two rows of blocks: cached teal blocks with locks reused from the first request, and new amber blocks computed fresh"
---

## The question

Have you ever noticed inconsistent response times during a Claude coding session? Or wondered why some API requests drain your credits much faster than others? You've come to the right place. 

If Claude is part of your daily workflow, let's explore some common habits that might be driving up your token usage and slowing down response time. 


## The mental model 

If you are a video game player (especially in open-world video games), you are already familiar with checkpoints (save points). You are not starting the game from the very beginning every time you boot your console. When your checkpoint (save point) is not available anymore on your console (for example, it got deleted), you are going to start the game from the very beginning. In the same way, prompt caching works. 

## How it works 

Let's first agree on some points: 
- **The model is stateless**. Every time you are sending a new prompt all of your context window is being sent to the server. 
- The context window consists of: tools, system prompts, project context, session context, and your messages. 

Let's look more closely at what is happening once you write a message and send it to the model. 


![Without prompt caching, request 2 recomputes everything from request 1 before the new reply and prompt](/images/decoding-prompt-caching/without-caching.png)

So you decide to open Claude then typed your first prompt and send it to Claude. Once the request is received, everything in the request is computed for the first time. Then again, you continue prompting Claude with another request that carries **the same computed part** plus two things not computed: the **reply** from your first prompt and **your new prompt**. Think of a 1M context window: how much does that cost you when you reach half of your context window? And how long will it take to do the computation for every request from the very beginning and reply to you? 

**That's why prompt caching matters.** 

![With prompt caching, request 2 reads the shared start from the cache and only computes the new reply and prompt](/images/decoding-prompt-caching/with-caching.png)

With prompt caching, the first request is fully computed. When a second request arrives, **only the new, trailing portion is processed**, while the previously computed part is reused from the cache. 

In other words, prompt caching eliminates the repeated work. 
### How does this prompt caching work under the hood? 

```mermaid
sequenceDiagram
    autonumber
    participant C as Client (Claude Code)
    participant A as API
    participant K as Cache

    Note over C,K: Request 1 (21k tokens in total)
    C->>A: tools + system (20k) [cache_control A] + your message 1 (1k) [cache_control B]
    A->>K: lookup prefix ending at B
    K-->>A: miss
    A->>A: process all 21k tokens, nothing to reuse
    A->>K: save entries A and B
    A-->>C: Claude reply 1 (usage: creation 21000, read 0)

    Note over C,K: Request 2 (whole history resent, 24k tokens in total)
    C->>A: tools + system (20k) [cache_control A] + your message 1 (1k) + Claude reply 1 + your message 2 [cache_control B moved here]
    A->>K: lookup prefix ending at your message 2, walking back up to 20 positions
    K-->>A: hit at your message 1 (the 21k saved by request 1)
    A->>A: reuse the 21k, process only Claude reply 1 + your message 2 (3k new tokens)
    A->>K: save entry for the prefix ending at your message 2
    A-->>C: Claude reply 2 (usage: creation 3000, read 21000)
```


You start a new Claude Code session and send your first message; the API request will hold three important data: 
1. System prompts, tools, and your message. 
2. A cache control indicator that identifies the very beginning of the request (tools and system prompts), which will never change during your session.
3. A cache control indicator that identifies the end of your request (your message), which will be changed in a future request (when you continue prompting Claude Code after Claude's first response).

On the server side, it will look up the cache by searching for a prefix ending with the cache control that indicates your message (cache control B). If the cache is **empty**, your request is fully processed from scratch. The system then saves the data between cache controls A and B before replying, though **the final generated response itself is not cached**. If a cache already **exists**, the system reuses it and only processes the new information such as your latest prompt and the previous response, before updating the cache and sending the reply.


> [!NOTE] 
> The lookup starts from the cache control indicator that identifies your message to Claude Code. 

### How the lookup is working 


```mermaid
flowchart TB
    R("Request 2 arrives<br/>hash of the prefix up to each block:<br/>H1 = tools + system<br/>H2 = message 1<br/>H3 = reply 1<br/>H4 = message 2 (cache_control)"):::req
    Q1("1. H4 saved?<br/>no"):::miss
    Q2("2. H3 saved?<br/>no"):::miss
    Q3("3. H2 saved?<br/>yes"):::found
    H("HIT<br/>reuse 21k, compute only 3k"):::hit
    C[("Saved by request 1<br/>H1 = tools + system<br/>H2 = up to message 1")]:::saved

    R --> Q1 --> Q2 --> Q3 --> H
    C -.-> Q3

    subgraph LEG[" "]
        direction LR
        L1("incoming"):::req
        L2("checked, no match"):::miss
        L3("checked, match"):::found
        L4[("saved in cache")]:::saved
        L1 ~~~ L2 ~~~ L3 ~~~ L4
    end
    H ~~~ L2

    classDef req fill:#FFF1D6,stroke:#E39A2D,color:#4A2E05
    classDef miss fill:#F1F2F4,stroke:#9AA1AB,color:#2B3038
    classDef found fill:#DDF3EA,stroke:#1F9D78,color:#0B3B2D
    classDef hit fill:#1F9D78,stroke:#0F6B52,color:#FFFFFF
    classDef saved fill:#E4EEFC,stroke:#4A86E0,color:#10305C
    style LEG fill:none,stroke:none
```

Claude identifies each block in your context window individually. By scanning backward from your latest message, it locates the first cached match, uses that as a starting point, and then calculates only the remaining, uncached blocks. 

### How Claude will behave in case of a cache miss 

Many scenarios can cause a cache miss, which we will cover shortly. The most common occurs when the cache's Time To Live (TTL) expires, forcing Claude to recompute the entire context window from the start.


```mermaid
flowchart TB
    E[("Saved by requests 1 and 2<br/>H1, H2, H4<br/>last used 6 min ago, TTL is 5 min<br/>EXPIRED")]:::expired
    R("Request 3 arrives<br/>H1 = tools + system<br/>H2 = message 1<br/>H3 = reply 1<br/>H4 = message 2<br/>H5 = reply 2<br/>H6 = message 3 (cache_control)"):::req
    Q("Look up H6, H5, H4, H3, H2, H1<br/>none saved"):::miss
    M("MISS<br/>compute all 27k tokens again"):::bad
    W[("Save a new entry for H6<br/>TTL clock restarts")]:::saved

    E -. "gone" .-> Q
    R --> Q --> M --> W

    subgraph LEG[" "]
        direction LR
        L1("incoming"):::req
        L2("checked, no match"):::miss
        L3[("expired entry")]:::expired
        L4("recompute"):::bad
        L5[("saved in cache")]:::saved
        L1 ~~~ L2 ~~~ L3 ~~~ L4 ~~~ L5
    end
    W ~~~ L3

    classDef req fill:#FFF1D6,stroke:#E39A2D,color:#4A2E05
    classDef miss fill:#F1F2F4,stroke:#9AA1AB,color:#2B3038
    classDef expired fill:#F1F2F4,stroke:#9AA1AB,stroke-dasharray:5 4,color:#6B7280
    classDef bad fill:#FBE1DC,stroke:#D9534F,color:#5C1A14
    classDef saved fill:#E4EEFC,stroke:#4A86E0,color:#10305C
    style LEG fill:none,stroke:none
```

You can configure your cache's TTL from Claude Code. Check it [here](https://code.claude.com/docs/en/prompt-caching#choose-the-ttl-yourself).

## Actions that invalidate the cache
- Switching models. 
- Changing efforts. 
- Turning on fast mode. 
- Connecting/Removing an MCP server.
- Enabling/Disabling a plugin.
- Denying an entire tool. 
- Compacting the conversation. 
- Accumulating many images. 
- Upgrading Claude Code. 

## Actions that keep the cache
- Editing files in your repository. 
- Editing `Claude.md` mid-session.
- Changing output style.
- Invoking skills/commands. 
- Running `/recap`.
- Running `/rewind`.
- Spawning a subagent. 
## Gotchas 
- Initially, I used a highly capable model like Opus 5.5 for planning. Once the agent and I agreed on an approach, I switched to the Sonnet model within the same session to begin implementation. However, this workflow increased both my costs and latency.
- While you can add a missing tool mid-session, I highly recommend ensuring all necessary tools are available from the start.
- Don't let your cache cool down. (Some Claude [mods](https://claudecodemods.dev/mods/prompt-cache-control--davila7) can let you know your cache is still warm or cold). 
- The lookup is limited to 20 blocks only, so if Claude's previous response and your new message is more than 20 blocks that will cause a cache miss. 

## Further reading 
- [Claude prompt caching](https://code.claude.com/docs/en/prompt-caching).
- [Prompt caching is everything](https://claude.dev/blog/lessons-from-building-claude-code-prompt-caching-is-everything/).

---

Bringing AI agents into your mobile team? See how I can [help](/work-with-me/).
