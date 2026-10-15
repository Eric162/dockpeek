import AppKit

enum AnimationPrompt {
  static let example = #"""
    {
      "version": 1,
      "descriptor": {
        "id": "custom.slide",
        "name": "Gentle slide",
        "stages": ["entry"],
        "settings": [
          {"id": "duration", "name": "Duration (seconds)", "kind": "number", "defaultValue": 0.35, "minimum": 0.05, "maximum": 15}
        ]
      },
      "keyframes": [
        {"time": 0, "curve": "linear", "travel": 0, "x": 0, "y": -64, "angle": 0, "squash": 1, "opacity": 1},
        {"time": 1, "curve": "easeOut", "travel": 1, "x": 0, "y": 0, "angle": 0, "squash": 1, "opacity": 1}
      ]
    }
    """#

  static var text: String {
    """
    Help me build a custom Dock Peek animation. Ask what motion I want, then return one
    complete .json file that I can import with Appearance → Install animation… and test.

    Plugins are declarative JSON, with no executable code or external assets. They animate
    the existing app icon and unread badge together. Do not add GIFs, emoji, or new layers.

    Start from this valid, minimal slide-style entry animation. Use a unique lowercase ID
    containing only a–z, digits, periods, or hyphens; slide, tumble, and none are reserved.

    \(example)

    Supported stages: entry and dismissal. Every plugin declares a numeric duration setting,
    with positive minimum/default/maximum values and a maximum of 15 seconds. Other settings
    can be number (minimum/maximum), toggle (boolean defaultValue), or choice (string
    defaultValue and a choices array). Each setting needs id, name, kind, and defaultValue.
    The host creates the settings controls automatically.

    Keyframes have strictly increasing normalized times from 0 to 1. Include every scalar:
    travel, x, y, angle, squash, opacity. Curves: linear, easeOut, easeInOut; the destination
    keyframe sets the curve. Geometry is in macOS points, Y upward; angle is in radians.
    travel moves from the initial point toward the host destination; x/y add offsets.
    Entry starts at the final origin, so offsets define its arrival path. Dismissal starts
    from the visible pose and travels below the screen. End entry at travel 1, x/y/angle 0,
    squash 1, opacity 1. The host always settles to its exact final pose.

    Scalars can also be {"binding":"height","multiplier":-0.25,"value":0}, meaning
    value + input * multiplier (defaults: value 0, multiplier 1). Bindings: width, height,
    unreadCount (0 if unknown), hasUnread (0/1), direction (-1 left / 1 right), entering
    (1 entry / 0 dismissal), setting.ID. Toggle settings bind as 0/1. Choice bindings need
    a complete numeric map: {"binding":"setting.direction","choices":{"up":0,"down":8}}.
    The panel is 128 points square, containing a 54-point icon and its host-rendered badge.
    screenTopOffset is screen.maxY minus the final panel origin Y. To drop from the top
    of the peek's display, use travel 1 and y {"binding":"screenTopOffset"} at time 0,
    then travel 1 and y 0 at time 1. This starts the panel just above the top edge and
    works on different display sizes and positions; height is only the panel height.

    Keep JSON under 64 KiB, with 2–256 keyframes, at most 16 settings and 16 choices each.
    All numbers must be finite. Keep opacity 0–1, squash 0.1–4, rotation within 50 turns,
    and positions within four panel widths of the screen. No nested expressions or loops.
    Built-in Slide eases toward the final pose. Built-in Tumble uses three shrinking hops
    and two full rotations; keyframes can approximate that motion, but native built-ins
    are not JSON files. Explain the controls and which stages your animation supports.
    """
  }
}

extension SettingsModel {
  func copyAnimationPrompt(to pasteboard: NSPasteboard = .general) {
    pasteboard.clearContents()
    if pasteboard.setString(AnimationPrompt.text, forType: .string) {
      message = "AI prompt copied. Paste it into your agent."
      error = false
    } else {
      message = "Could not copy the AI prompt. Try again."
      error = true
    }
  }
}
