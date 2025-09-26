---
title: "Stop Writing Boilerplate Analytics Code (Your Future Self Will Thank You)"
date: 2025-09-24T12:00:00+00:00
draft: false
description: "Eliminate 95% of your analytics tracking code with compile-time bytecode injection. No runtime overhead, just clean automated analytics."
categories: ["Android", "Gradle-plugin"]
tags: ["android", "analytics", "gradle", "kotlin", "bytecode", "asm"]
author: "Mohamed Shalan"
featuredImage: "/images/analytics-annotation-library-hero.jpg"
featuredImagePreview: "/images/analytics-annotation-library-hero.jpg"
---

We've all been there. You're deep in the flow, building that perfect user experience, when suddenly you remember: "Oh right, I need to track this screen." Then comes the familiar ritual—add the analytics call, remember the lifecycle method, serialize the parameters, and pray you didn't miss any edge cases. Rinse and repeat for every single screen and action in your app.

**What if I told you there was a better way?**

## The Problem We All Share

Let's be honest: analytics tracking is essential but tedious. Every Android developer has written code that looks like this:

```kotlin
class ProductDetailActivity : AppCompatActivity() {
    @Inject lateinit var analyticsService: AnalyticsService
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // The analytics code we all write (and sometimes forget)
        val params = mapOf(
            "screen_name" to "product_detail",
            "product_id" to productId,
            "category" to category
        )
        analyticsService.trackScreen("screen_view", params)
        
        setContentView(R.layout.activity_product_detail)
        // Your actual feature code starts here...
    }
    
    private fun onAddToCartClicked() {
        // More analytics boilerplate for user actions
        try {
            analyticsService.trackEvent("add_to_cart", mapOf(
                "product_id" to productId,
                "price" to price,
                "quantity" to selectedQuantity
            ))
        } catch (e: Exception) {
            // Don't crash the app for analytics
        }
        
        // The actual business logic
        shoppingCart.addItem(productId, selectedQuantity)
    }
}
```

Even with dependency injection and clean abstractions, you're still manually calling analytics everywhere. Your business logic gets polluted with tracking concerns, and you constantly worry: "Did I remember to track this action? Did I pass the right parameters?"

Multiply this by dozens of screens and hundreds of user actions, and suddenly 30% of your codebase is analytics boilerplate. We're better than this.

## A Simple Annotation Changes Everything

What if tracking your screens was as simple as this?

```kotlin
@TrackScreen(screenName = "product_detail")
class ProductDetailActivity : AppCompatActivity(), TrackedScreenParamsProvider {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_product_detail)
        // That's it. Analytics tracking is automatic.
    }
    
    @Track(eventName = "add_to_cart")
    private fun onAddToCartClicked(
        @Param("product_id") productId: String,
        @Param("price") price: Double,
        @Param("quantity") quantity: Int
    ) {
        // Just your business logic - tracking happens automatically
        shoppingCart.addItem(productId, quantity)
    }
    
    // Optional: provide dynamic parameters
    override fun getTrackedScreenParams(): Map<String, Any> {
        return mapOf(
            "product_id" to productId,
            "category" to category
        )
    }
}
```

**Here's the magic**: At compile time, a Gradle plugin uses ASM bytecode manipulation to inject the analytics tracking code exactly where it needs to be. No runtime overhead, no reflection, no performance impact—just clean, automatically tracked analytics.

The same principle works everywhere:

```kotlin
// Fragments? Covered.
@TrackScreen(screenName = "user_profile")
class ProfileFragment : Fragment()

// Jetpack Compose? Of course.
@TrackScreenComposable(screenName = "settings")
@Composable
fun SettingsScreen() { /* Your UI code */ }

// Any class with business logic? Absolutely.
@Trackable
class ShoppingCartService @Inject constructor(
    private val repository: CartRepository
) {
    @Track(eventName = "item_added_to_cart")
    fun addItem(@Param("product_id") id: String, @Param("quantity") qty: Int) {
        // Pure business logic - tracking happens automatically
        repository.addItem(id, qty)
    }
}
```

## How It Works (The Technical Magic)

![Technical Magic](/images/easy-analytics-annotations/easy-analytics-annotations-technical-magic.png)

[**The Easy-Analytics**](https://github.com/sh3lan93/analytics-annotation) Gradle plugin uses a multi-pronged approach:

**1. Compile-Time Transformation**: A Gradle plugin scans your code for annotations and uses ASM to inject analytics calls directly into your bytecode. For screen tracking, the injected code runs after lifecycle methods like `onCreate()` or `onViewCreated()`. For method tracking, analytics calls are injected at the beginning of `@Track` annotated methods with automatic parameter serialization.

**2. Provider Pattern**: Your analytics calls go through a clean provider interface, so you can use Firebase, Mixpanel, or any custom analytics service without changing your tracking code.

**3. Zero Runtime Cost**: Since everything happens at compile time, there's no performance penalty. No reflection, no runtime annotation scanning—just the analytics code you would have written manually.

## Setup Is Refreshingly Simple

```kotlin
// 1. Apply the plugin
plugins {
    id("dev.moshalan.easyanalytics") version "1.0.0"
}

// 2. Initialize once in your Application class
ScreenTracking.initialize(analyticsConfig {
    providers.add(FirebaseAnalyticsProvider())
    providers.add(DebugLogProvider()) // For development
})

// 3. Just annotate your screens and methods
@TrackScreen(screenName = "home")
class MainActivity : AppCompatActivity()
```

## What This Means for Your Team

**For developers**: Write 95% less analytics code. Focus on features, not tracking boilerplate.

**For QA**: Debug mode shows exactly what's being tracked, making verification effortless.

**For performance**: Zero runtime overhead means your app stays fast while gaining comprehensive analytics.

## The Bottom Line

We built this Gradle plugin because we were tired of writing the same analytics code over and over. Modern Android development deserves modern solutions—and sometimes that means letting the computer handle the repetitive stuff while we focus on building great user experiences.

[**The Easy-Analytics**](https://github.com/sh3lan93/analytics-annotation) Gradle plugin isn't revolutionary because it does something impossible. It's valuable because it eliminates something annoying that we all do every day. And honestly? That might be even better.

---

**Ready to try it?** The Gradle plugin is open source (Apache 2.0) with comprehensive documentation and examples. Check out the complete project on GitHub: [Easy-Analytics](https://github.com/sh3lan93/analytics-annotation)

*What's the most tedious part of your current analytics setup? I'd love to hear how you're solving (or suffering through) analytics tracking in your projects.*