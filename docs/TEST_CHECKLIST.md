# SDM Browser – manual test checklist

Go through this list on a real phone after a new build and report anything that fails.

## Tabs and live panel
- [ ] Open the browser: homepage shows SDM wordmark, search box, shortcuts.
- [ ] Search "flutter" -> Google results open; the toolbar shows `google.com`.
- [ ] Tap a result: toolbar URL, tab title and favicon in the Tabs panel update.
- [ ] While a page loads, the Tabs panel shows "Loading… N%" and a progress line.
- [ ] Press Back: page goes back, title/URL in the panel update.
- [ ] Tab counter shows the right number; tap it -> left panel opens.
- [ ] Opening/closing the panel does NOT reload the page.
- [ ] "+" opens a new tab (homepage). Switch between tabs: both keep their page.
- [ ] Close a tab with X; close the last tab -> a fresh homepage tab appears.
- [ ] Panel bottom: Back / Home / Forward / + work.
- [ ] Home button shows homepage; Back returns to the page that was open.
- [ ] Open a link with target=_blank: it opens in a new tab.
- [ ] Close the app and reopen the browser: tabs and active tab come back.

## Menu
- [ ] Quick row: Back, Forward, Bookmark (star toggles), Refresh, Settings.
- [ ] New Tab, Return to SDM (near the top), History, Find in Page, Clear Browsing Data work.
- [ ] The Home icon next to the menu opens the browser start page.
- [ ] Block Ads / Capture Audio-Video / Desktop Mode show a check when ON and
      are still ON after restarting the app.
- [ ] Desktop Mode reloads the page as a desktop site.
- [ ] Tapping outside the menu closes it.
- [ ] View Page Resources lists requests for the current page.

## Downloads from the browser
- [ ] Tap a direct file link (e.g. a .zip / .pdf): SDM popup appears with the
      right name, type and size.
- [ ] Confirm -> item appears in Downloads, progress/speed move, pause/resume work.
- [ ] A link that returns an HTML page is refused with a clear message.
- [ ] A finished file opens and its size matches the server size.
- [ ] Airplane mode mid-download -> item shows Failed/Paused, Resume continues.

## Errors
- [ ] Open a non-existing domain: "Can't open this page" with Try again.
- [ ] http:// site shows an open-lock icon, https:// shows a closed lock.

## Top bar, Share app, About
- [ ] The browser icon and the three-dot menu are always shown.
- [ ] Menu -> Share app opens the Android share sheet; the receiver gets DROM.apk.
- [ ] Menu -> About shows the logo, the version and a "Check for update" button.
- [ ] After a new build is released, "Check for update" in About shows the update and its download starts by itself with live MB / % / speed; when done, the home page shows "Update ready" with Install, and it installs over the old one.
- [ ] With no new build, "Check for update" says there is no new update.

## Notifications and background
- [ ] Start a big download: the notification bar shows the file name, "NN% - X MB / Y MB - speed" and a progress bar.
- [ ] Start two downloads: each gets its own notification, plus a "2 downloads" summary with Pause all.
- [ ] Press Pause on ONE download's notification: only that one stops, its button changes to Resume, the other keeps going.
- [ ] Press Resume on it: it continues. Pause all / Resume all in the summary affect every download.
- [ ] Pause the only running download from its notification: the notification stays (paused) with Resume.
- [ ] Press Home: the download keeps going.
- [ ] Swipe the app away from recent apps: the notification stays and the download keeps going.
- [ ] Open the app again from the notification: it shows the running downloads.
- [ ] A finished download posts "Download complete"; tapping it opens SDM.
- [ ] Turn on Wi-Fi only, switch to mobile data: notification shows "Waiting for Wi-Fi".
