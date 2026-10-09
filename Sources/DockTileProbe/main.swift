import AppKit
@preconcurrency import ApplicationServices

// Isolated integration fixtures use the same executable and subprocess path.
if let index = CommandLine.arguments.firstIndex(of: "--verify-root"),
  CommandLine.arguments.indices.contains(index + 1)
{
  let root = URL(fileURLWithPath: CommandLine.arguments[index + 1])
  guard
    FileManager.default.fileExists(
      atPath: root.appendingPathComponent(".dockpeek-verification").path)
  else { exit(1) }
  let mode = try? String(contentsOf: root.appendingPathComponent("probe-mode"), encoding: .utf8)
  if mode == "hang" { Thread.sleep(forTimeInterval: 30) }
  if mode == "fail" { exit(3) }
  guard
    let text = try? String(contentsOf: root.appendingPathComponent("snapshot.txt"), encoding: .utf8)
  else { exit(1) }
  print(text)
  exit(0)
}

if CommandLine.arguments.contains("--request-access") {
  let options =
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    as CFDictionary
  let trusted = AXIsProcessTrustedWithOptions(options)
  print(
    trusted
      ? "Accessibility access is already enabled."
      : "Enable Dock Tile Probe in the macOS permission list.")
  if !trusted,
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
  {
    NSWorkspace.shared.open(url)
  }
  exit(trusted ? 0 : 2)
}

// Icon extraction is independent of Accessibility permission.
if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--icon-only" {
  let image = NSWorkspace.shared.icon(forFile: CommandLine.arguments[2])
  guard let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
  else { exit(1) }
  do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    print("Saved icon to \(CommandLine.arguments[3])")
    exit(0)
  } catch {
    fputs("\(error)\n", stderr)
    exit(1)
  }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
  var result: CFTypeRef?
  return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success
    ? result : nil
}

guard AXIsProcessTrusted() else {
  fputs(
    "Accessibility permission is required for this executable; no prompt was requested.\n", stderr)
  exit(2)
}
guard
  let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
else {
  fputs("Dock is not running.\n", stderr)
  exit(1)
}

func inspect(_ element: AXUIElement, depth: Int) {
  guard depth < 4 else { return }
  var names: CFArray?
  guard AXUIElementCopyAttributeNames(element, &names) == .success else { return }
  let keys = names as? [String] ?? []
  print(String(repeating: " ", count: depth * 2) + "ELEMENT")
  for key in keys
  where !["AXChildren", "AXParent", "AXTopLevelUIElement", "AXWindow"].contains(key) {
    if let value = attribute(element, key) {
      print(String(repeating: " ", count: depth * 2) + "\(key)=\(value)")
    }
  }
  for child in attribute(element, "AXChildren") as? [AXUIElement] ?? [] {
    inspect(child, depth: depth + 1)
  }
}

inspect(AXUIElementCreateApplication(dock.processIdentifier), depth: 0)
