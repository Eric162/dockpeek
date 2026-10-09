import AppKit
import Darwin

// Experimental LaunchServices state cancellation, not a pre-animation interceptor.
// No settings changes, activation, Accessibility permission, or code injection.
typealias CreateASN = @convention(c) (CFAllocator?, pid_t) -> Unmanaged<CFTypeRef>?
typealias CopyItem = @convention(c) (Int32, CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
typealias SetItem =
  @convention(c) (
    Int32, CFTypeRef, CFString, CFTypeRef, UnsafeMutablePointer<Unmanaged<CFDictionary>?>?
  ) -> Int32

func fail(_ message: String) -> Never {
  fputs("\(message)\n", stderr)
  exit(1)
}

func load<T>(_ name: String, from handle: UnsafeMutableRawPointer, as type: T.Type) -> T {
  guard let address = dlsym(handle, name) else { fail("Missing private API: \(name)") }
  return unsafeBitCast(address, to: type)
}

var allowed: Set<String> = ["com.openai.codex"]
var duration = 60.0
var enforce = false
var onlyBundle: String?
var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
  let argument = arguments.removeFirst()
  switch argument {
  case "--enforce": enforce = true
  case "--allow", "--duration", "--only-bundle":
    guard !arguments.isEmpty else { fail("Missing value for \(argument)") }
    let value = arguments.removeFirst()
    if argument == "--allow" {
      allowed = Set(value.split(separator: ",").map(String.init))
      guard !allowed.isEmpty else { fail("Allowlist must not be empty") }
    } else if argument == "--only-bundle" {
      onlyBundle = value
    } else {
      guard let seconds = Double(value), seconds.isFinite, seconds > 0 else {
        fail("Duration must be a positive number of seconds")
      }
      duration = seconds
    }
  case "--help":
    print("Usage: dock-bounce-filter [--allow id,id] [--duration seconds] [--enforce]")
    print("Defaults: observe only, 60 seconds, allow com.openai.codex.")
    print("--only-bundle id restricts experiments to one disposable app.")
    exit(0)
  default: fail("Unknown argument: \(argument)")
  }
}

let path =
  "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices"
guard let handle = dlopen(path, RTLD_NOW) else { fail("Cannot load LaunchServices") }
defer { dlclose(handle) }
let createASN = load("_LSASNCreateWithPid", from: handle, as: CreateASN.self)
let copyItem = load("_LSCopyApplicationInformationItem", from: handle, as: CopyItem.self)
let setItem = load("_LSSetApplicationInformationItem", from: handle, as: SetItem.self)
let attentionKey = CFStringCreateWithCString(
  nil, "LSWantsAttention", CFStringBuiltInEncodings.UTF8.rawValue)!
var reported: Set<pid_t> = []
let deadline = ProcessInfo.processInfo.systemUptime + duration
print(
  "\(enforce ? "Cancelling" : "Observing") attention; allowed: \(allowed.sorted().joined(separator: ", ")); duration: \(duration)s"
)
fflush(stdout)

while ProcessInfo.processInfo.systemUptime < deadline {
  autoreleasepool {
    var pending: Set<pid_t> = []
    for application in NSWorkspace.shared.runningApplications {
      guard application.activationPolicy == .regular,
        let bundle = application.bundleIdentifier,
        onlyBundle == nil || onlyBundle == bundle,
        let asn = createASN(nil, application.processIdentifier)?.takeRetainedValue(),
        let value = copyItem(-2, asn, attentionKey)?.takeRetainedValue(),
        CFGetTypeID(value) == CFBooleanGetTypeID(),
        CFEqual(value, kCFBooleanTrue)
      else { continue }
      let pid = application.processIdentifier
      pending.insert(pid)
      let permitted = allowed.contains(bundle)
      if !reported.contains(pid) {
        print("\(permitted ? "ALLOW" : "BLOCK") \(bundle) pid=\(pid)")
        fflush(stdout)
      }
      if enforce && !permitted {
        let status = setItem(-2, asn, attentionKey, kCFBooleanFalse, nil)
        guard status == 0 else { fail("Cannot clear \(bundle): OSStatus \(status)") }
        guard let updated = copyItem(-2, asn, attentionKey)?.takeRetainedValue(),
          CFEqual(updated, kCFBooleanFalse)
        else { fail("Attention remained set for \(bundle)") }
        print("CLEARED \(bundle)")
        fflush(stdout)
      }
    }
    reported = pending
  }
  // Polling means an initial animation can escape before this cancellation.
  // NSWorkspace needs its run loop serviced to discover newly launched apps.
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
