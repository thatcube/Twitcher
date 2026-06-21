# Twizz Privacy Policy

**Last updated: June 21, 2026**

Twizz is a free, open-source Apple TV app for watching Twitch, with optional
support for YouTube and Kick. This policy explains what Twizz accesses, where it
goes, and what it does not do. The short version: Twizz has no servers of its
own, runs everything on your Apple TV, and never sells or shares your data.

> Replace `https://thatcube.github.io/Twizz/` and the contact email below with
> your real hosted URL and support address before submitting for Google
> verification.

## Who runs Twizz

Twizz is maintained by thatcube. It is not affiliated with or endorsed by Twitch
Interactive, Inc., Google LLC, YouTube, or Kick.

Contact: `support@example.com` (update before publishing).

## The basics

- Twizz has **no backend server** and **no Twizz account**. There is nothing to
  sign up for with us.
- Twizz includes **no analytics, no telemetry, no advertising, and no crash
  reporting** SDKs. We do not track you.
- Everything Twizz stores stays **on your Apple TV**. We never receive it.
- We never **sell, rent, or share** your data with third parties for advertising
  or any other purpose.

## What Twizz stores on your device

All of this lives only on your Apple TV and is never sent to us:

- **Sign-in tokens** for Twitch (and, if you choose, Google/YouTube), stored in
  the system Keychain and refreshed automatically.
- **Your preferences**: theme, chat appearance, quality, per-feature toggles, and
  similar settings.
- **Watch history**, used only on-device to power "Recommended for you." You can
  turn personalized recommendations off, which stops this from being used.

You can clear all of it at any time by signing out and/or deleting the app.

## YouTube sign-in (optional)

YouTube sign-in is **optional**. Twizz works fully without it. If you choose to
connect your YouTube account, here is exactly what happens:

- **Scope requested:** `https://www.googleapis.com/auth/youtube.readonly` only.
  This is read-only. Twizz cannot post, comment, modify, upload, subscribe, or
  change anything on your YouTube account.
- **What we read:** your YouTube **subscriptions** and whether those channels are
  **currently live** (and their live viewer counts).
- **Why:** so Twizz can show which of the channels you subscribe to on YouTube
  are live right now, alongside the Twitch channels you follow.
- **Where it goes:** these requests go directly from your Apple TV to YouTube's
  official APIs. The results are used on-device to build the live list and are
  cached briefly on the device. They are **never sent to a Twizz server** (there
  isn't one) and are **never shared** with anyone.
- **Revoke any time:** sign out of YouTube inside Twizz, or remove Twizz's access
  at <https://myaccount.google.com/permissions>. Revoking immediately stops all
  further access.

### Limited Use disclosure (Google API Services)

Twizz's use of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the **Limited Use** requirements. Specifically, data obtained through
the YouTube `youtube.readonly` scope is used **only** to provide and improve the
in-app feature that shows your live YouTube subscriptions, is **not** transferred
to others except as required to provide that feature, is **not** used for
advertising, and is **not** sold. No humans read this data except as needed for
security or to comply with the law, and we do not retain it beyond what the
feature needs.

## Other services Twizz talks to

Because Twizz is a viewer for live platforms, your Apple TV connects directly to
these services as you use the app. We do not operate any of them, and we do not
add ourselves in the middle:

- **Twitch** — for sign-in, your follows, stream listings, playback, and chat.
- **YouTube / Google** — only if you connect YouTube, as described above.
- **Kick** — public, anonymous read of chat for channels you watch (experimental
  chat merge). No Kick sign-in.
- **Emote and badge providers** (7TV, BetterTTV, FrankerFaceZ) — to fetch the
  public emote and badge images shown in chat.
- **A public catalog file hosted on GitHub** (`raw.githubusercontent.com`) — a
  static, read-only list Twizz downloads to know which channels simulcast. It
  contains no personal data and is the same for everyone; downloading it sends us
  nothing about you.

Each of these services has its own privacy policy that governs its handling of
your data once your device contacts it.

## Children's privacy

Twizz is not directed at children under 13 and does not knowingly collect data
from them. It collects no personal data on our behalf at all.

## Changes to this policy

If this policy changes, we'll update the date at the top and post the new version
at the URL above. Material changes will be reflected here.

## Contact

Questions about privacy? Reach us at `support@example.com` (update before
publishing) or open an issue at <https://github.com/thatcube/Twizz>.
