# wallnetic.app

The `site/` folder is the whole website: static HTML and CSS, one small
script for the clock, no build step, no web fonts and no third-party
requests. It is a placeholder while the full site is built.

## Pages

| Path | Content |
|------|---------|
| `/` | One page: the app, a note that the site is under construction, and links to the Mac App Store, GitHub and support |
| `/support/` | Contact (`support@wallnetic.app`, GitHub Issues) and common questions |
| `/privacy` | Redirects to `PRIVACY.md` on `main`, so the policy has one source |
| `/support/issues`, `/github`, `/app-store` | Short redirects |
| any other path | `404.html` |

Redirects are in `site/_redirects` and stay temporary (302), so the site can
host its own pages later. `site/_headers` sets a strict Content Security Policy:
only the site's own styles, script and images.

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

## Content rules

The site follows the same rules as the release text: describe what the App
Store version does, give no CPU, energy or savings figures, and do not
advertise unreleased or unavailable features.
