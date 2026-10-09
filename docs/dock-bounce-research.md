> Archived investigation from the original scratch prototype. Current source lives in Sources and Experiments.

# Per-app Dock bounce filtering research

Research date: 2026-10-08. This document records web evidence only; local runtime findings belong in the coordinator's investigation.

## Finding

AppKit exposes no documented cross-process attention filter, but the Apple-authored `lsappinfo(8)` manual documents a promising LaunchServices observation and mutation path. The coordinator discovered it in the installed manual; the web manual independently confirms it. This may support a utility that clears unwanted attention requests without injection. It is cancellation after a state change, not a synchronous interception hook; preventing even the first animation frame requires measured validation.

## Promising LaunchServices path

The `lsappinfo(8)` manual documents `listen +wantsAttentionChanged` notifications for changes to `LSWantsAttention`, plus `setinfo -app SPEC KEY=value` for another app's information. Applications can be specified by ASN, PID, name, or bundle ID; Boolean false is accepted as a value. The manual also lists `kLSApplicationDesiresAttentionKey` and `applicationVisualNotification`. [Apple-authored manual, hosted mirror](https://keith.github.io/xcode-man-pages/lsappinfo.8.html)

Candidate experiment: listen for attention changes, resolve the affected ASN's bundle ID, and clear `LSWantsAttention` for apps outside the allowlist. The manual establishes the commands and notification; it does not promise that mutating this flag cancels native Dock animation, that every bounce uses this key, or that cancellation always wins the rendering race. Test both critical and informational AppKit requests, repeated requests, and simultaneous allowed/blocked apps. The installed OS manual and fixture behavior are stronger evidence for this computer than the web mirror's older documentation.

## Supported API and the actual interception seam

- AppKit's `NSApplication.requestUserAttention(_:)` starts an attention request and returns an integer that the requester can pass to `cancelUserAttentionRequest(_:)`. Activation cancels the request; an already active app's request has no effect. An inactive app opening a modal panel triggers a critical request automatically. [Apple request API](https://developer.apple.com/documentation/appkit/nsapplication/requestuserattention(_:))
- Cancellation is an instance method on `NSApplication`; its parameter is the returned request ID, without an app/PID target. This is not a documented cross-process cancellation facility. [Apple cancellation API](https://developer.apple.com/documentation/appkit/nsapplication/canceluserattentionrequest(_:))
- Apple explicitly documents overriding `requestUserAttention:` in an application's own `NSApplication` subclass to replace the bouncing behavior. This is a clean interception seam when you control the app. For a third-party app, an Objective-C method swizzle or lower-level interposition would require code inside that process. [Apple NSApplication override guidance](https://developer.apple.com/documentation/appkit/nsapplication?language=objc)
- The Desktop & Dock setting **Animate opening applications** controls launch bouncing. It is a different trigger from the running app asking for attention. [Apple Desktop & Dock settings](https://support.apple.com/en-gb/guide/mac-help/mchlp1119/mac)

## Private API evidence

The cDock developer's reverse-engineered CoreDock header includes `CoreDockSetLaunchAnimationsEnabled(Boolean)` and global Dock preference/appearance calls. It does not include per-app attention observation, interception, or cancellation. This is only evidence about that published header; additional private symbols may exist in the installed OS. The developer describes using Frida and partial headers to discover these APIs. [Developer's research](https://www.macenhance.com/blog/2021/coredock.html), [published CoreDock header](https://gist.github.com/w0lfschild/90db263867f469738c01e9e2d937f874)

## Injection constraints

Apple says hardened runtime and SIP prevent classes of code injection and memory tampering. The relevant exceptions include allowing DYLD environment variables, disabling library validation, and debugging permissions; these are entitlements of the target executable, not powers granted merely by choosing Swift or Rust. [Apple hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime)

For SIP-protected system processes, attachment and `task_for_pid` fail, DYLD variables are purged, and even root LLDB attachment is denied. This makes injecting a filter into the system Dock an invasive approach rather than a normal user utility. [Apple SIP runtime protections](https://developer.apple.com/library/archive/documentation/Security/Conceptual/System_Integrity_Protection_Guide/RuntimeProtections/RuntimeProtections.html)

## Practical implications and proposed experiments

1. Preserve the current preference while testing. Distinguish launch bounce from attention bounce with a small owned AppKit probe.
2. Prioritize the documented `lsappinfo` observation/mutation route above. Inspect underlying LaunchServices symbols only if subprocess latency makes its cancellation too slow.
3. Test whether Dock Accessibility attributes or notifications expose attention state. Reading a badge is not evidence of a bounce request. A post-animation observer cannot guarantee preventing the first bounce.
4. If a private PID-targeted cancellation API exists, test it against the owned probe first and check whether it cancels pre-render or only stops an ongoing critical bounce.
5. If no safe private route exists, keep global bouncing disabled and build an allowlisted alternative signal (menu-bar flash, custom overlay, or notification) driven by an event available from ChatGPT. This preserves the attention goal but does not bounce ChatGPT's native Dock tile.

Activating unwanted apps to cancel their requests would steal focus. Temporarily enabling global bouncing whenever ChatGPT is running would admit other applications during the same interval. Neither implements the requested allowlist.

## Unconfirmed internet workaround

A Stack Overflow answer claims deleting an app's `NSUserNotificationAlertStyle` prevents bounce requests. No Apple source establishes that relationship; AppKit documents attention requests independently of notification presentation. Treat that suggestion as unverified and do not recommend it without an owned-probe test.
