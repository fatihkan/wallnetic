# Wallnetic Privacy Policy

**Last updated:** October 2026

## Overview

Wallnetic is a macOS application that allows you to use video files as live desktop wallpapers. We are committed to protecting your privacy.

## Data Collection

**We do not collect any data.**

Wallnetic:
- Does not collect personal information
- Does not track usage or analytics
- Does not send crash reports to external servers
- Does not add advertising identifiers or usage analytics
- Does not require an account
- Supports local imports and playback entirely offline

## Local Storage

Your wallpaper library and application preferences are stored locally on your Mac:

### Video Files
Your imported wallpaper videos are stored in:
```
~/Library/Application Support/Wallnetic/Library
```
In the App Store version this folder is inside Wallnetic's app container,
`~/Library/Containers/com.wallnetic.app/Data/`.

### App Preferences
Your settings are stored using macOS standard preferences (UserDefaults):
- Theme preference (Dark/Light/System)
- Playback settings (pause on battery, pause on fullscreen)
- Launch at login preference
- Per-display wallpaper assignments
- Last selected wallpaper

### Collections & Favorites
Your wallpaper collections and favorites are stored locally.

### Thumbnail Cache
Video thumbnails are cached locally for faster loading.

**Important:** We do not have access to any of this data. There is no cloud sync or external storage.

## Network Access

Local imports and playback do not require an internet connection. Wallnetic connects to the internet only when you use one of the optional features below. It does not send your library contents, preferences or any identifiers to us, and we do not operate servers that receive data from the app.

### Optional wallpaper packs

Opening the pack catalog uses bundled or locally saved previews without making a network request. Choosing **Refresh Catalog** contacts `raw.githubusercontent.com` to retrieve the Wallnetic catalog. Choosing **Download Pack / Download / Retry** contacts the same host to download the selected media from the public `fatihkan/wallnetic` repository.

These requests disclose ordinary connection information to GitHub, including your IP address, requested URL and request time. The pack feature sends no library contents, account details or tracking identifiers, uses no cookies or stored credentials, and performs no background catalog polling. Saved catalogs, download ownership records and downloaded copies remain on your Mac. GitHub operates the host under its [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

### Discover (in-app browser)

Opening a wallpaper website in Discover loads that site in Wallnetic's built-in browser, as any web browser would. The site receives ordinary connection information, such as your IP address and the pages you request, and it can store cookies and other website data in Wallnetic's app container on your Mac. Videos you choose to download are saved to your Wallnetic library. Each website has its own privacy policy.

### Importing from a link

If you open a `wallnetic://import` link and confirm the import, Wallnetic downloads the file from the HTTPS address in the link. That server receives ordinary connection information, such as your IP address and the requested address.

### Create from Photos

Create from Photos reads the photos you select, after you allow access to your Photos library, and builds a slideshow wallpaper from them on your Mac. If a selected photo is stored in iCloud Photos, macOS may download it from iCloud for Wallnetic. The slideshow is saved to your Wallnetic library; nothing is uploaded.

### App Store

**Rate Wallnetic** opens Wallnetic's App Store page, and macOS may show Apple's rating prompt. Apple handles these under its own privacy policy.

### No other connections

This version has no other network features, such as AI services or update checks. You can keep using local wallpapers without any of the features above.

## App Permissions

Wallnetic requests the following macOS permissions:

| Permission | Purpose |
|------------|---------|
| File Access | To import and play video files you select |
| Photos | Optional - to build a slideshow from photos you select (Create from Photos) |
| Notifications | Optional - only if you turn on notifications |
| Accessibility | Optional - only if you turn on global keyboard shortcuts, so they work while another app is active; Wallnetic looks only for its own shortcuts |
| Login Items | Optional - to launch at system startup |

Showing wallpapers on your desktop needs no permission. These permissions are used solely for the features listed.

## Data Security

Your data is protected by macOS security features:

- **App Sandbox:** the App Store version runs in a sandboxed environment, isolated from other apps. The direct-download version from GitHub is ad-hoc signed and not sandboxed
- **Secure Storage:** All data is stored using macOS secure storage mechanisms
- **Local Library:** Wallnetic does not upload your imported videos or library metadata

## Third-Party Services

Optional wallpaper packs use GitHub hosting. Wallnetic does not include analytics platforms, advertising networks or tracking tools. Websites you open in Discover, iCloud Photos and the App Store are separate services with their own privacy policies.

## Children's Privacy

Wallnetic does not collect any information from anyone, including children under 13. The app is safe for users of all ages and is rated 4+ on the App Store.

## Your Rights

Since we don't collect any data, there is no personal data to access, modify, or delete. You can:

- Delete all local data by uninstalling the app
- Clear your wallpaper library through the app
- Remove app permissions in System Settings > Privacy & Security

## Changes to This Policy

We may update this Privacy Policy from time to time. Any changes will be posted on this page with an updated revision date.

## Contact

If you have any questions about this Privacy Policy, please contact us:

- **GitHub:** [github.com/fatihkan/wallnetic](https://github.com/fatihkan/wallnetic)
- **Twitter:** [@KanFatih](https://twitter.com/KanFatih)
- **LinkedIn:** [linkedin.com/in/fatihkan](https://www.linkedin.com/in/fatihkan)

---

**Wallnetic**
© 2026 All rights reserved.
