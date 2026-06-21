# Google OAuth Consent Screen & Verification Notes

Reference for getting Twizz's YouTube sign-in out of **Testing** and into
**Production** (verified). Twizz requests exactly one YouTube scope, which is
**sensitive** (not restricted), so verification needs brand/identity review,
a privacy policy, and a demo video — but **no** CASA security assessment.

> Fill in the real homepage, privacy-policy URL, and support email before
> submitting. The placeholders below assume GitHub Pages hosting.

## App identity (OAuth consent screen)

| Field | Value |
| --- | --- |
| App name | `Twizz` |
| User support email | `support@example.com` (update) |
| App logo | The Twizz logo (square, on a solid background) |
| Application home page | `https://thatcube.github.io/Twizz/` (update) |
| Privacy policy URL | `https://thatcube.github.io/Twizz/privacy-policy` (update) |
| Authorized domain | `thatcube.github.io` (must be verified in Search Console) |
| User type | External |
| Publishing status | In production (submit for verification) |
| OAuth client type | TVs and Limited Input devices |
| Developer contact | your email |

## Scopes (request the minimum — this is the single most important thing)

Request **only**:

```
https://www.googleapis.com/auth/youtube.readonly
```

Do **not** add `youtube`, `youtube.force-ssl`, `youtube.upload`, or any other
scope. Asking for more than the app visibly uses is the most common reason
sensitive-scope verification is rejected.

## Scope justification (paste-ready)

Use this for the per-scope justification field. It must match what the demo
video shows.

> **Scope:** `https://www.googleapis.com/auth/youtube.readonly`
>
> Twizz is an Apple TV app for watching live streams. After a user optionally
> signs in with their Google account on the TV (using the device-code flow for
> limited-input devices), Twizz calls the YouTube Data API to read the user's
> own subscriptions and determine which of those channels are currently live,
> including each live channel's concurrent viewer count. Twizz uses this solely
> to display the user's live YouTube subscriptions inside the app, alongside the
> Twitch channels they follow, so they can see everything that's live in one
> place and start watching.
>
> The scope is read-only. Twizz never creates, edits, deletes, uploads,
> comments, rates, or subscribes. The data is requested directly from the user's
> device to YouTube's APIs, used only on-device to build the live list, cached
> briefly on the device, and never sent to any server we operate (we operate
> none) or shared with third parties. Users can revoke access at any time from
> within the app or at myaccount.google.com/permissions.

## "Why do you need access?" / app-function summary (paste-ready)

> Twizz is a free, open-source TV viewer for live streaming. The YouTube
> integration is an optional feature: if the user connects their Google account,
> Twizz reads their YouTube subscriptions and live status (read-only) and shows
> which subscribed channels are live now. This lets a user see their Twitch and
> YouTube follows that are live in a single home screen on Apple TV. No data is
> stored on our servers — the app has no backend — and nothing is shared or sold.

## Demo video script (required for sensitive scopes)

Record a short screen capture (or TV capture) that shows, in order:

1. The Twizz home screen, signed out of YouTube.
2. Starting YouTube sign-in: the device-code / QR screen.
3. Completing approval at `youtube.com/activate`, **clearly showing the Google
   OAuth consent screen with the app name "Twizz" and the requested
   `youtube.readonly` permission.**
4. Back in Twizz: the app now showing the user's **live YouTube subscriptions**
   listed alongside Twitch follows — i.e., the exact use of the scope.
5. Signing out of YouTube (or revoking), showing the data goes away.

Keep it under ~2 minutes, no cuts that hide the consent screen, and make sure the
OAuth client ID / app name on the consent screen matches the app being verified.

## Pre-submission checklist

- [ ] Homepage is live at the URL above and describes the app (not just a repo).
- [ ] Privacy policy is live at its URL and is reachable from the homepage.
- [ ] Privacy policy includes the **Limited Use** disclosure (it does — see
      `docs/privacy-policy.md`).
- [ ] Authorized domain is **verified** in Google Search Console with the same
      Google account that owns the Cloud project.
- [ ] Only `youtube.readonly` is requested; no extra scopes linger in the config.
- [ ] App name, logo, and support email on the consent screen are final and
      consistent with the video.
- [ ] Demo video recorded per the script above and uploaded/linked.
- [ ] Scope justification text submitted and matches the video.

## Notes on timing and expectations

- Sensitive-scope verification typically takes days to a few weeks and often
  comes back once or twice with change requests (usually privacy-policy wording
  or video clarity). Respond promptly and it moves along.
- Staying in **Testing** is not viable for a shipped app: it caps at 100 test
  users and refresh tokens expire after 7 days.
- A YouTube Data API **quota-increase request** triggers a separate YouTube API
  compliance review, so avoid needing one. The default 10,000 units/day is
  plenty for the cheap calls this feature makes
  (`playlistItems.list` at 1 unit/channel, batched `videos.list` at ~1 unit/50).
