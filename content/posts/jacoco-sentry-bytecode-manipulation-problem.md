---
date: '2025-10-13T23:25:04+04:00'
draft: false
title: 'When Your Test Coverage Lies to You: A Bytecode Murder Mystery'
tags: ["android", "testing", "JaCoCo", "Sentry", "debugging"]
categories: ["Engineering", "Android"]
author: "Mohamed Shalan"
featuredImage: "/images/bytecode-manipulation.jpg"
featuredImagePreview: "/images/bytecode-manipulation.jpg"
description: "Your test coverage is showing 0% despite passing tests. Here's how JaCoCo and Sentry's bytecode instrumentation conflict—and the simple fix."
---

The pull request was routine—merging some changes I'd already tested thoroughly. Then [**Codacy's coverage gate**](https://www.codacy.com/) blocked me: "Insufficient coverage on modified paths." 

I stared at the failure message. Those paths *were* covered. I'd written the tests myself. Watched them pass. Green checkmarks everywhere except this one gate, claiming I'd forgotten to test code that I *knew* I'd tested.

Fine. I'll prove it. I ran the coverage report locally. `./gradlew jacocoTestReport` and waited for the HTML output, already composing my "actually, the CI is wrong" Slack message in my head.

The report loaded.

**0%.**

I laughed. Not a "that's funny" laugh. More of a "my computer has achieved sentience and chosen chaos" laugh. Zero percent coverage. Every single line marked red, as if I'd spent my afternoon writing tests in invisible ink.

But here's the thing: **the tests were passing**. The code was executing. I could watch it happen in the debugger. **The coverage data just... wasn't there**. Like showing up to a concert with a valid ticket and being told you're not on the list.

That's when the caffeine kicked in and I realized: something was *eating* my coverage data.

## The Invisible Saboteur (Or: When Two Plugins Fight Over the Same Territory)

Here's the thing about bytecode instrumentation that nobody tells you until it ruins your Tuesday: multiple tools can't touch the same compiled code without stepping on each other's toes. 

Imagine you're writing an essay in a shared document. Your colleague opens it and adds their comments directly into the text—not as suggestions, but by actually changing your sentences. Then another colleague opens that modified version and does the same thing. When you finally see the document, you can't tell what you originally wrote versus what got changed. Except instead of an essay, it's your compiled bytecode, and instead of helpful colleagues, it's Gradle plugins having a turf war over who gets to modify what.

In my case, two tools were fighting over my `.class` files:

**JaCoCo** wanted to inject coverage probes—tiny markers that track which lines of code executed during tests. Think of them as those "You Are Here" stickers on mall maps, except for your codebase.

**Sentry** wanted to inject performance monitoring—code that measures how long methods take and captures execution context. Basically, it wants to time everything like an obsessive sports coach with a stopwatch.

Both plugins modify bytecode. Both run during the build. And when they both touch the same file? JaCoCo generates a report comparing its coverage data against bytecode it no longer recognizes. The checksums don't match. The structure is different. From JaCoCo's perspective, it's like coming home to find your furniture rearranged and insisting you've never lived there.

The error message was wonderfully unhelpful: `[ant:jacocoReport] Classes in bundle 'app' do not match with execution data.`

Translation: "I have no idea what you tested, so I'm just going to tell everyone you tested nothing. Hope that's cool."

## Why This Matters (And Why It'll Keep You Up at Night)

The dangerous part isn't the error itself—it's the silence. **Our CI didn't fail.** The build didn't break. The only signal was coverage numbers lying with the confidence of a politician during election season.

This is the kind of issue that makes you question everything. If coverage reports can be wrong by 70 percentage points and nobody notices, what else is quietly broken? Should I have become a carpenter like my parents suggested?

And here's the kicker: **this happens at the bytecode level, invisible to most developers**. You can't see it in your source code. You can't catch it in code review. It only surfaces when you're deep enough in the build process to notice the numbers don't add up.

I spent years trusting coverage reports the way you trust your GPS—never expecting it to just *make up a destination*.

## The Race Condition Nobody Documents (A Five-Act Tragedy)

Let me walk you through what was actually happening, because understanding the mechanism makes the solution obvious.

**Act 1:** Gradle compiles your Kotlin/Java source into `.class` files—pure, unmodified bytecode. Everything is beautiful and innocent.

**Act 2:** The Sentry plugin injects its instrumentation—method entry points, timing code, context capture. It's like adding director's commentary to your movie, except nobody asked for it.

**Act 3:** The JaCoCo plugin *also* injects its instrumentation—coverage probes, execution markers. Now we've got commentary on the commentary.

**Act 4:** Your tests execute against this doubly-instrumented bytecode. JaCoCo writes coverage data to an `.exec` file. Everything seems fine. The tests pass.

**Act 5 (The Plot Twist):** The `jacocoTestReport` task compares the `.exec` file against the `.class` files. But the checksums don't match what JaCoCo expects, because Sentry modified the structure first. JaCoCo looks at everything, shrugs, and reports zero coverage.

It's a race condition disguised as a compatibility issue, wearing a trench coat and sunglasses.

## The Fix: Surgical, Not Scorched Earth

The obvious solution—disabling Sentry entirely—is the software equivalent of burning down your house because you found a spider. We need Sentry's crash reporting in production. We don't need its performance instrumentation during coverage runs. 

So we disable *just the instrumentation* when running JaCoCo tasks:

```gradle
sentry {
    org = "your-org"
    projectName = "your-app"
    includeSourceContext = true
    
    tracingInstrumentation {
        // Disable when running jacoco tasks to prevent conflicts
        enabled = !gradle.startParameter.taskNames.any { 
            it.toLowerCase().contains('jacoco') 
        }
        features = EnumSet.allOf(InstrumentationFeature) - 
                   InstrumentationFeature.DATABASE - 
                   InstrumentationFeature.FILE_IO
    }
}
```

If any task includes "jacoco" in its name, Sentry's bytecode instrumentation is disabled. JaCoCo gets clean bytecode. Coverage reports become accurate.

The beauty: it's conditional. Debug builds still get full Sentry instrumentation. Production builds still get monitoring. Only coverage builds run with Sentry's tracing disabled.

It's like giving each plugin its own room instead of making them share.

## What You Can Take Away Tomorrow

If you're running into mysteriously inaccurate coverage reports, here's your diagnostic checklist:

1. **Look for bytecode instrumentation conflicts.** Any plugin that modifies `.class` files (code coverage, performance monitoring, AOP frameworks) is a potential culprit.

2. **Check your plugin execution order.** Gradle doesn't guarantee ordering unless you explicitly configure it. Two plugins modifying bytecode in undefined order is asking for trouble.

3. **Make your build configuration task-aware.** The `gradle.startParameter.taskNames` API lets you conditionally enable/disable features based on what you're actually trying to accomplish.

4. **Trust, but verify your metrics.** If a number suddenly changes without corresponding code changes, the metric is suspect. Don't assume developer behavior changed—investigate the measurement first.

5. **Document the "why" not just the "what."** When you fix something like this, write down the mechanism. Future you (or your teammates) will need to understand the conflict when the next instrumentation tool gets added.

## The Broader Pattern (Or: This Will Happen to You Again)

This specific issue is about JaCoCo and Sentry, but the pattern is universal: **tools that operate at the same level of abstraction will conflict unless you explicitly coordinate them.**

It shows up everywhere:
- Multiple JavaScript bundlers transforming the same modules
- Competing ORM frameworks managing database connections
- Different logging libraries capturing the same stack traces
- Linters and formatters disagreeing about code style

The solution is always the same: understand what each tool is *actually doing*, and architect your build so they don't step on each other. Sometimes that means running them at different times. Sometimes it means disabling features. Sometimes it means picking one.

In our case, test coverage and performance monitoring are fundamentally incompatible during the same build. You measure one or the other, never both simultaneously. Like measuring the temperature of your coffee while drinking it—one activity will mess up the other.

---

**The bottom line:** Your coverage reports are only as trustworthy as the instrumentation that generates them. When two tools fight over the same bytecode, both lose—and you lose worst of all because you're the one staring at nonsense metrics wondering if you're going insane.

The fix isn't always "disable one tool"—sometimes it's "disable one tool *when running the other*." Like having separate game night and book club nights instead of trying to play Monopoly while discussing Dostoevsky. Both are great. Neither works well simultaneously.

Now when I see our coverage metrics, I know they mean something. That PR eventually merged, Codacy shut up, and I got to keep both my test coverage and my crash monitoring. 

Worth every hour of debugging. (That's a lie. But I'm glad it's fixed.)
