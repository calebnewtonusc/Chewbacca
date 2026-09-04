// Turn on the accessibility tree for Chromium/Electron apps, which build it lazily.
// Sets AXManualAccessibility on the application element. Returns JSON per app.
// Usage: osascript -l JavaScript lib/force-ax.js [AppName]
ObjC.import('Cocoa')
ObjC.bindFunction('AXUIElementCreateApplication', ['id', ['int']])
ObjC.bindFunction('AXUIElementSetAttributeValue', ['int', ['id', 'id', 'id']])

function run(argv) {
  const want = (argv[0] || '').toLowerCase()
  const apps = $.NSWorkspace.sharedWorkspace.runningApplications
  const out = []
  for (let i = 0; i < apps.count; i++) {
    const a = apps.objectAtIndex(i)
    const name = ObjC.unwrap(a.localizedName) || ''
    if (want && name.toLowerCase() !== want) continue
    if (!want && parseInt(a.activationPolicy) !== 0) continue // regular apps only
    const pid = parseInt(a.processIdentifier)
    const el = $.AXUIElementCreateApplication(pid)
    const manual = $.AXUIElementSetAttributeValue(
      el, $('AXManualAccessibility'), $.NSNumber.numberWithBool(true))
    let enhanced = null
    if (manual !== 0) {
      enhanced = $.AXUIElementSetAttributeValue(
        el, $('AXEnhancedUserInterface'), $.NSNumber.numberWithBool(true))
    }
    out.push({ app: name, pid: pid, AXManualAccessibility: manual,
               AXEnhancedUserInterface: enhanced,
               ok: manual === 0 || enhanced === 0 })
  }
  // 0 = kAXErrorSuccess. -25208 = kAXErrorAttributeUnsupported (app is not Chromium).
  return JSON.stringify(out, null, 2)
}
