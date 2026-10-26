// Logs Wallnetic's desktop windows from outside the app, for the window
// checks in #306 (slice 2): opening and closing windows, Hide Dock icon,
// switching apps, Hide (Command-H), lock/unlock. Works on any build, needs no
// developer tools and asks for no permission.
//
// Run:  osascript -l JavaScript tools/desktop-window-probe.js [--once]
//       [--interval seconds] [--bundle-id id] | tee probe.log
//
// It prints the macOS build, the Mac model and the displays, then one line
// whenever the app's activation policy, active or hidden state changes, and
// whenever a desktop window's level, alpha, on-screen state or frame changes.
// A desktop window is one first seen at the overlay level (desktop icons - 1);
// `pinned` means it is still there. occlusionState is not visible from
// outside the app, so also note what the wallpaper looks like. Polling adds
// WindowServer work, so do not run this during a benchmark session.
ObjC.import('AppKit');
ObjC.import('CoreGraphics');

const DESKTOP_ICON_LEVEL_KEY = 18; // kCGDesktopIconWindowLevelKey
const POLICIES = ['regular', 'accessory', 'prohibited'];

function run(argv) {
  const option = (name, fallback) => {
    const i = argv.indexOf(name);
    return i >= 0 && i + 1 < argv.length ? argv[i + 1] : fallback;
  };
  const bundleID = option('--bundle-id', 'com.wallnetic.app');
  const interval = Number(option('--interval', '0.2'));
  const overlayLevel = $.CGWindowLevelForKey(DESKTOP_ICON_LEVEL_KEY) - 1;

  const version = $.NSProcessInfo.processInfo.operatingSystemVersionString.js.replace(/^Version /, '');
  out(`# ${new Date().toString()}; macOS ${version}; ${shell('sysctl -n hw.model')}`);
  out(`# displays (top-left origin, like window frames): ${displays()}`);
  out(`# watching ${bundleID}; overlay level ${overlayLevel}`);

  const tracked = new Set();
  const last = new Map();
  const report = (key, state) => {
    if (last.get(key) === state) return;
    last.set(key, state);
    out(`${clock()} ${key}: ${state}`);
  };

  do {
    const app = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(bundleID).js[0];
    if (!app) {
      report('app', 'not running');
    } else {
      report('app', `policy=${POLICIES[Number(app.activationPolicy)] ?? app.activationPolicy}`
        + ` active=${yesNo(app.active)} hidden=${yesNo(app.hidden)}`);
      const pid = Number(app.processIdentifier);
      const windows = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(0, 0)))
        .filter(w => w.kCGWindowOwnerPID === pid);
      const seen = new Set();
      for (const w of windows) {
        if (w.kCGWindowLayer === overlayLevel) tracked.add(w.kCGWindowNumber);
        if (!tracked.has(w.kCGWindowNumber)) continue;
        seen.add(w.kCGWindowNumber);
        const b = w.kCGWindowBounds;
        const layer = w.kCGWindowLayer === overlayLevel ? 'pinned' : `DROPPED(${w.kCGWindowLayer})`;
        report(`window ${w.kCGWindowNumber}`, `layer=${layer} alpha=${w.kCGWindowAlpha}`
          + ` onscreen=${yesNo(w.kCGWindowIsOnscreen)} frame=${b.X},${b.Y} ${b.Width}x${b.Height}`);
      }
      for (const number of tracked) {
        if (!seen.has(number)) report(`window ${number}`, 'GONE');
      }
    }
    if (!argv.includes('--once')) delay(interval);
  } while (!argv.includes('--once'));
}

function yesNo(value) {
  return value === true ? 'yes' : 'no';
}

// NSScreen frames have a bottom-left origin on the primary display; window
// bounds have a top-left one.
function displays() {
  const screens = $.NSScreen.screens.js;
  const primaryHeight = screens.length ? screens[0].frame.size.height : 0;
  return screens.map(screen => {
    const f = screen.frame;
    const top = primaryHeight - f.origin.y - f.size.height;
    return `${f.size.width}x${f.size.height}@${screen.backingScaleFactor}x at ${f.origin.x},${top}`;
  }).join(', ');
}

function shell(command) {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;
  return app.doShellScript(command);
}

function clock() {
  const now = new Date();
  const pad = (value, width = 2) => String(value).padStart(width, '0');
  return `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`
    + `.${pad(now.getMilliseconds(), 3)}`;
}

function out(line) {
  $.NSFileHandle.fileHandleWithStandardOutput
    .writeData($(line + '\n').dataUsingEncoding($.NSUTF8StringEncoding));
}
