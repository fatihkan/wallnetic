# wallnetic.app

The `site/` folder is the whole website:
- static HTML and CSS;
- one small script for the demo desktop;
- our own media;
- no build step, no web fonts and no third-party requests.

## Pages

| Path | Content |
|------|---------|
| `/` | The product page:<br>• hero with the Mac App Store badge, GitHub link and requirements line<br>• a demo Mac desktop<br>• compatibility (Intel, Apple silicon, macOS 13–26)<br>• four reasons and a list of other features<br>• FAQ<br>• final call to action |
| `/support/` | Contact (`support@wallnetic.app`, GitHub Issues) and common questions |
| `/privacy` | Redirects to `PRIVACY.md` on `main`, so the policy has one source |
| `/support/issues`, `/github`, `/app-store` | Short redirects |
| any other path | `404.html` |

### Files

| File | Role |
|------|------|
| `site.css` | Shared styles for every page. Light by default, dark with the system. Glass surfaces use `backdrop-filter` with a solid fallback and honour Reduce Transparency. |
| `site.js` | The demo desktop:<br>• the desktop clock and menu bar clock show the visitor's time<br>• the wallpaper video plays only with Reduce Motion off, and pauses off screen or in a hidden tab<br>• the Calm Mode button holds it<br>The page works without it. |
| `media/lagoon.mp4` | The demo wallpaper: the MIT-licensed `catalog/media/lagoon.mp4`, remuxed with `+faststart` (same video stream, about 350 KB) |
| `media/*.jpg` | The poster (first frame) and two stills for the per-display card |
| `img/og.jpg` | The 1200×630 share image, a capture of the demo desktop |
| `img/mac-app-store-badge*.svg` | Apple's official Mac App Store badges, black and white, unmodified and self-hosted |

All media is Wallnetic's own (see `catalog/media/README.md`). Never use
third-party artwork, characters or brands on the site. The App Store
screenshots in `docs/assets/` contain some, so they are not reused here.

Redirects are in `site/_redirects` and stay temporary (302), so the site can
host its own pages later. `site/_headers` sets a strict Content Security Policy:
only the site's own styles, script, images and media (`media-src 'self'`).

## Store and app links

These addresses are meant for App Store Connect and the app:

- Marketing URL: `https://wallnetic.app`
- Support URL: `https://wallnetic.app/support/`
- Privacy Policy URL: `https://wallnetic.app/privacy`

Settings > About in the app links to `https://wallnetic.app` and
`mailto:support@wallnetic.app`. Cloudflare Email Routing forwards the support
address.

## Hosting

Cloudflare Pages, project `wallnetic`, with the custom domains `wallnetic.app`
and `www.wallnetic.app`. Deploy the folder as it is:

```sh
CLOUDFLARE_API_TOKEN=… CLOUDFLARE_ACCOUNT_ID=… \
  npx wrangler@4.151.0 pages deploy site --project-name wallnetic --branch main
```

The token needs Cloudflare Pages edit access on the account. Never commit it.

Link to `wallnetic.app`, never to `wallnetic.pages.dev`: some Turkish internet
providers answer `*.pages.dev` lookups with a block page, while the custom
domain resolves normally.

Everything used is on Cloudflare's free plan: Pages direct uploads (no builds),
DNS, Email Routing, and the `_redirects` and `_headers` files. The site uses no
Workers, Functions or paid add-ons.

## Content rules

The site follows the same rules as the release text: describe what the App
Store version does, give no CPU, energy or savings figures, and do not
advertise unreleased or unavailable features.
