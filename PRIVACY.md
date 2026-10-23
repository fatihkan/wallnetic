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

### Other optional connections

Opening external wallpaper sources or using optional network/AI integrations contacts the websites or providers you choose. Those services have their own privacy policies and may receive the requests and inputs needed for the selected action. You can continue using local wallpapers without using these features.

## App Permissions

Wallnetic requests the following macOS permissions:

| Permission | Purpose |
|------------|---------|
| File Access | To import and play video files you select |
| Screen Access | To display wallpapers on your desktop |
| Login Items | Optional - to launch at system startup |

These permissions are used solely for the app's core functionality.

## Data Security

Your data is protected by macOS security features:

- **App Sandbox:** Wallnetic runs in a sandboxed environment, isolated from other apps
- **Secure Storage:** All data is stored using macOS secure storage mechanisms
- **Local Library:** Wallnetic does not upload your imported videos or library metadata

## Third-Party Services

Optional wallpaper packs use GitHub hosting. Wallnetic does not include analytics platforms, advertising networks or tracking tools. Websites you open in Discover and other optional providers are separate services with their own privacy policies.

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
