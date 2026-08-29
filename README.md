> [!NOTE]  
> **This is a fork of [kieraneglin/pinchflat](https://github.com/kieraneglin/pinchflat).** No
> affiliation with the original author, no endorsement from them, and no changes submitted back.
> Images live at `ghcr.io/morgankryze/pinchflat`. Read
> [About this fork](#about-this-fork) for what differs and for the AI disclosure.

> [!IMPORTANT]  
> (2025-02-14) [zakkarry](https://github.com/sponsors/zakkarry), who is a collaborator on [cross-seed](https://github.com/cross-seed/cross-seed) and an extremely helpful community member in general, is facing hard times due to medical debt and family illness. If you're able, please consider [sponsoring him on GitHub](https://github.com/sponsors/zakkarry) or donating via [buymeacoffee](https://tip.ary.dev). Tell him I sent you!

<p align="center">  
  <img 
    src="priv/static/images/originals/logo-white-wordmark-with-background.png" 
    alt="Pinchflat Logo by @hernandito"
    width="700" 
  />
</p>

<p align="center">  
  <sup>
    <em>logo by <a href="https://github.com/hernandito" target="_blank">@hernandito</a></em>
  </sup>
</p>

<div align="center">

[![](https://img.shields.io/github/license/kieraneglin/pinchflat?style=for-the-badge&color=ee512b)](LICENSE)
[![](https://img.shields.io/github/v/release/kieraneglin/pinchflat?style=for-the-badge&color=purple)](https://github.com/kieraneglin/pinchflat/releases)
[![](https://img.shields.io/static/v1?style=for-the-badge&logo=discord&message=Chat&color=5865F2&label=Discord)](https://discord.gg/j7T6dCuwU4)
[![](https://img.shields.io/github/actions/workflow/status/kieraneglin/pinchflat/lint_and_test.yml?style=for-the-badge)](#)
[![](https://img.shields.io/static/v1?label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode&style=for-the-badge)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/kieraneglin/pinchflat)

</div>

# Your next YouTube media manager

## About this fork

Upstream is good software and nothing below is a complaint about it. This fork fixes what breaks
when you point Pinchflat at an existing back catalogue instead of at new uploads. That keeps the
queue busy for weeks, and a queue that stays busy is where quiet failures stop being theoretical.

Upstream has been paused since early 2026, so nothing here waits on review.

### What's changed

| Change                                                                                                                        | Why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tell an IP throttle apart from an age restriction ([`adf908f`](https://github.com/MorganKryze/pinchflat/commit/adf908f))      | Pinchflat matched `"Sign in to confirm"` as a prefix. It covers two opposite messages: `…your age` never succeeds, `…you're not a bot` clears within hours. Both were dropped, and dropping one returned `{:ok, :non_retry}`, which Oban records as a success. The media item kept its error and lost its last job. Throttles now take the ordinary retry path, and you set how many attempts and how far apart.                                                                                  |
| Rescue jobs orphaned without a restart ([`095af1d`](https://github.com/MorganKryze/pinchflat/commit/095af1d))                 | Upstream resets `executing` jobs at boot, which covers a container that stops and starts. It does not cover a job whose execution ends while the node keeps running, and the download worker's uniqueness covers `:executing`, so nothing can queue a replacement for that media item until something hands it back. `Oban.Plugins.Lifeline` does, after two hours, long enough that a slow download never looks like a dead one.                                                                 |
| Write the NFO air date as a date ([`706c98b`](https://github.com/MorganKryze/pinchflat/commit/706c98b))                       | `<aired>` carried a full DateTime. Jellyfin parses that field in the exact format its `ReleaseDateFormat` setting names, `yyyy-MM-dd` by default, so the string never matched and episodes arrived with no air date. Titles, plots and thumbnails all came through, which is why you never suspect the NFO.                                                                                                                                                                                       |
| Stop discarding the result of the yt-dlp self-update ([`3aa28e9`](https://github.com/MorganKryze/pinchflat/commit/3aa28e9))   | The update worker called `update/0`, dropped the return value, and answered `:ok` whatever happened. A self-update failing every day logged a successful job every day. The only sign was a yt-dlp as old as the image it shipped in, and an out-of-date yt-dlp answers `Sign in to confirm you're not a bot`, which reads like an IP ban and sends you to inspect your network. The job now fails, and keeps when it last tried and what went wrong.                                             |
| Record why a media item was set aside ([`585033a`](https://github.com/MorganKryze/pinchflat/commit/585033a))                  | Setting `prevent_download` left no trace. A `media_pre_download` script returning non-zero set the flag and wrote nothing: no log line, no reason. The media item went quiet and you had to read your own script to learn why. `blocked_reason` records it, and nothing later clears it, since it explains something no job will attempt again.                                                                                                                                                   |
| Give forced retries a priority you can set ([`d28560f`](https://github.com/MorganKryze/pinchflat/commit/d28560f))             | Oban sorts by priority before `scheduled_at`, so a forced retry lands behind everything already queued. On a busy source that is days of waiting. The priority became a setting, still starting at upstream's value, so you can say you mean now.                                                                                                                                                                                                                                                 |
| Say how old an error is ([`d5ee4cc`](https://github.com/MorganKryze/pinchflat/commit/d5ee4cc))                                | `last_error` survives until the next attempt on that item, which can take days, and the interface showed it with no date. A throttle that cleared last week read like one happening now. A wrong message with nothing to date it costs you more time than no message.                                                                                                                                                                                                                             |
| Stop asking while YouTube is refusing ([`9f4a642`](https://github.com/MorganKryze/pinchflat/commit/9f4a642))                  | A throttled request fails in milliseconds. Nothing downloads, so nothing slows down, and the queue burns through refusals at full speed while the block feeds on them. Off by default. Turn it on and the four yt-dlp queues stop for a set time once enough downloads are refused with none getting through. Stopping the download queue alone would leave indexing and metadata calling the same blocked address.                                                                               |
| Make failures readable, from one list ([`139494d`](https://github.com/MorganKryze/pinchflat/commit/139494d))                  | Three modules kept their own list of yt-dlp error strings, and the lists disagreed. That is how one prefix came to cover two opposite messages. One table now says, per failure, whether a retry could work, whether cookies could help, and what you should read. yt-dlp writes hundreds of characters, and Pinchflat poured them into a tooltip wide enough for a sentence. The short name leads, the raw text waits on the detail page.                                                        |
| Give a source a tab for what went wrong ([`9591ef0`](https://github.com/MorganKryze/pinchflat/commit/9591ef0))                | The tabs were Pending, Downloaded and Other. None answers "what failed", which is the first question on a library of any size, and the answer used to be a SQL query you wrote yourself. Errored covers anything carrying a failure, whatever happened to it after. Something that failed and was then set aside still shows up, since those need explaining most.                                                                                                                                |
| Optionally stop retrying what can never work ([`d4d2a56`](https://github.com/MorganKryze/pinchflat/commit/d4d2a56))           | A deleted, private, members-only or age-gated video comes back at every index, and clearing each one costs a click. Off by default. Turn it on and the failure takes the item out of rotation with its reason recorded. There is no bulk action here on purpose: the items stop needing clicks. Throttles stay out of it, since setting one aside turns a block that clears in hours into a permanent gap.                                                                                        |
| Report whether anything is being downloaded ([`d714e7b`](https://github.com/MorganKryze/pinchflat/commit/d714e7b))            | `/healthcheck` answers "the web server is up", which is all a container probe should ask. Everything that matters lived in the database, where you look only once you already suspect something. A token-protected `/healthcheck/details` reports downloads and failures in a window, how many were throttles, when a download last succeeded, items that should download with no job that ever will, items set aside with no reason, and whether the queues are stopped on purpose.              |
| Say on the dashboard when something needs looking at ([`2402a99`](https://github.com/MorganKryze/pinchflat/commit/2402a99))   | The dashboard counted four kinds of success and no kind of trouble, so a library losing media looked like one that was fine. A fifth tile counts what carries a failure, and an Errors tab sits beside Downloaded and Pending so the number leads somewhere. It takes colour only above zero, because a dashboard that shouts at a healthy instance teaches you to stop reading it.                                                                                                               |
| Add an API for the things scripts were scraping ([`d6d6b35`](https://github.com/MorganKryze/pinchflat/commit/d6d6b35))        | Anything a script wanted came out of the HTML: a CSRF token pulled from a page, forms that blank any field you forget. `/sources` could not be listed at all, being a LiveView paging ten at a time over a websocket, so you walked ids until enough 404s came back. `/api/v1` serves sources and media as JSON and accepts the two writes a script needs, queueing downloads and setting an item aside. Responses and writes are both explicit allowlists, so adding a column publishes nothing. |
| Optionally stop the NFO repeating the channel name ([`528e68f`](https://github.com/MorganKryze/pinchflat/commit/528e68f))     | An episode title ending in " - Channel Name" repeats what the series is already called, and a source declared on a /videos tab reports as "Whatever - Videos", where the suffix names the tab. Both optional and off by default. The stripping stays narrow: a separator-delimited prefix or suffix, and yt-dlp's own tab names, so a channel called "Golden Moustache (M6)" survives. NFO only, since the interface should show what YouTube called it.                                          |
| Optionally tidy the description the NFO carries ([`64f15ca`](https://github.com/MorganKryze/pinchflat/commit/64f15ca))        | A YouTube description is mostly links and subscription pleas, and a media centre shows it as the episode summary. Optional and off by default. URLs come out while the sentences around them stay, because "Out on DVD March 7th! (pre-order here `<link>`)" is content with an appendage, and dropping whole lines empties a tenth of them. A line goes once the strip leaves it with no letters or digits. Length can be capped at a word boundary.                                             |
| Let one profile restrict filenames without imposing it ([`6c296b7`](https://github.com/MorganKryze/pinchflat/commit/6c296b7)) | `restrict_filenames` was global, so a library that wants accents and one that wants ASCII could not coexist, and unifying an existing one meant re-downloading it. Now a per-profile choice of inherit, restrict or allow, starting at inherit. It never applies to what is already on disk: restricting strips accents as well as spaces, and you cannot undo that from the name.                                                                                                                |
| Make the production image buildable again ([`2b7a061`](https://github.com/MorganKryze/pinchflat/commit/2b7a061))              | `selfhosted.Dockerfile` pinned ffmpeg to a 2024 autobuild. Those get pruned, the URL now 404s, and nobody could build the image from source. `curl` without `-f` wrote the 404 page into the archive and exited 0, so the build died further down in `tar` looking like a corrupt download. It now reads the `latest` release, which is what `dev.Dockerfile` already did.                                                                                                                        |
| Publish under this account, and prove it ([`4332bba`](https://github.com/MorganKryze/pinchflat/commit/4332bba))               | Upstream's release workflow hardcodes its own registries. Rebuilt for GHCR alone: actions pinned to commits with Dependabot behind them, the buildkit builder pinned by digest and watched weekly, tests gating the push on the same ref, and images signed with cosign carrying SLSA provenance and an SBOM. `stable` and `latest` move onto a digest only after its signature verifies.                                                                                                         |

Tagged releases are signed and carry `stable`, `latest` and their version number. Builds cut from
`master` by hand carry `dev` and a commit sha and go unsigned, since they are whatever `master` is
that minute.

Verify a release before running it. **Use cosign 3.0 or newer.** Releases are signed with
cosign 3, which stores a signature as an OCI referrer; cosign 2 looks for a `.sig` tag
instead, finds nothing, and says `no signatures found`, which reads like tampering rather
than like the version mismatch it is.

```bash
cosign verify ghcr.io/morgankryze/pinchflat:stable \
  --certificate-identity-regexp '^https://github.com/MorganKryze/pinchflat/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Running it, and going back

Verify the image before you run it. That is what the signing is for, and a version tag is
immutable where `stable` moves under you:

```bash
cosign verify ghcr.io/morgankryze/pinchflat:2026.8.29 \
  --certificate-identity-regexp '^https://github.com/MorganKryze/pinchflat/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

**The first boot copies your database before it migrates.** SQLite runs in WAL mode here, so
the copy goes through `VACUUM INTO` rather than through the filesystem, and you get a
consistent single file whatever state the write-ahead log is in. It lands beside the
database as `pinchflat.pre-migration-<timestamp>.db`. A boot with nothing pending copies
nothing. Delete the file once the upgrade has proven itself; nothing prunes it for you.

A failed copy stops the boot rather than migrating without it. The copy needs about as
much free space as the database uses, so a full disk is the realistic cause, and the log
says as much. Set `SKIP_MIGRATION_BACKUP=1` if you would rather migrate anyway, having
copied the database yourself.

Once it is up, ask it what it knows. The token is in the OPML feed URL on any source page:

```bash
curl -s "http://<host>:8945/healthcheck/details?route_token=<token>" | jq
```

Three fields tell you the most on a library coming from upstream. `pending_without_job`
counts media items that should download with no job that ever will. `set_aside_without_reason`
counts what was silently taken out of rotation. `yt_dlp_last_update_error` says whether the
self-update has been failing where nobody could see it.

Leave every setting alone through the first index cycle. The defaults match upstream, so
that run shows you the same behaviour you already had with instruments attached. Turn
options on one at a time afterwards, so a change in behaviour has one candidate.

**Going back to an upstream image** takes one command. Every migration this fork adds only
adds columns, so rolling them back drops those columns and leaves everything upstream wrote
untouched:

```bash
docker stop <container>
docker run --rm -v /host/path/to/config:/config \
  ghcr.io/morgankryze/pinchflat:2026.8.29 /app/bin/rollback_fork_migrations
```

It copies the database again first, under `pinchflat.pre-rollback-<timestamp>.db`, so the
snapshot from the upgrade survives. After it runs, the upstream image opens the database
without complaint.

### Defaults

**Out of the box this fork behaves like upstream.** Every preference starts at upstream's value, so
an update changes nothing about how your instance behaves until you ask it to. Retry counts, retry
spacing, forced-retry priority, queue backoff, automatic set-aside and the NFO options all sit in
Settings. The orphaned-job rescue window lives in `ORPHANED_JOB_RESCUE_MINUTES`, because Oban reads
its plugin config once at boot and a database field would look adjustable without being.

Four things change with no switch, because upstream did not choose them: a prefix matching two
opposite error messages, a date format no media centre parses, a return value dropped on the floor,
and a pinned URL that no longer resolves. Hiding those behind a flag would ship a default install
that stays broken.

### Still on the list

Passing the yt-dlp config cascade to indexing and metadata rather than to downloads alone. A
`timeout/1` on the download worker, which would let the orphan rescue window come down. And episode
numbering, where `s2013e110762` is the price of chronological ordering and every alternative
renumbers your library the next time a video appears.

### AI disclosure

[Claude Code](https://www.anthropic.com/claude-code) wrote the code in this fork, working from a
written specification, reviewed change by change before each one landed.

Three things you can check rather than take on trust:

- **Someone measured the problems before describing them.** Each one came from running the software
  and counting what it did.
- **The agent's claims went back against the source, and several were wrong.** The yt-dlp update
  worker _is_ on a daily cron and the yt-dlp config cascade _is_ wired up. Both had real defects,
  and both differed from what the first pass claimed. That happened before any code was written.
- **Every commit passes `mix check`**: the full test suite, Credo, Sobelow and formatting. Commit
  messages carry the reasoning and the trade-off, including the places this fork departs from a
  suggestion made upstream.

Report bugs here, not to upstream.

## Table of contents:

- [About this fork](#about-this-fork)
- [What it does](#what-it-does)
- [Features](#features)
- [Screenshots](#screenshots)
- [Installation](#installation)
  - [Unraid](#unraid)
  - [Portainer](#portainer)
  - [Docker](#docker)
  - [Environment Variables](#environment-variables)
  - [A note on reverse proxies](#reverse-proxies)
- [Username and Password (authentication)](https://github.com/kieraneglin/pinchflat/wiki/Username-and-Password)
- [Frequently asked questions](https://github.com/kieraneglin/pinchflat/wiki/Frequently-Asked-Questions)
- [Documentation](https://github.com/kieraneglin/pinchflat/wiki)
- [EFF donations](#eff-donations)
- [Pre-release disclaimer](#pre-release-disclaimer)
- [Development and Contributing](https://github.com/kieraneglin/pinchflat/wiki/Development-and-Contributing)

## What it does

Pinchflat is a self-hosted app for downloading YouTube content built using [yt-dlp](https://github.com/yt-dlp/yt-dlp). It's designed to be lightweight, self-contained, and easy to use. You set up rules for how to download content from YouTube channels or playlists and it'll do the rest, periodically checking for new content. It's perfect for people who want to download content for use in with a media center app (Plex, Jellyfin, Kodi) or for those who want to archive media!

While you can [download individual videos](https://github.com/kieraneglin/pinchflat/wiki/Frequently-Asked-Questions#how-do-i-download-one-off-videos), Pinchflat is best suited for downloading content from channels or playlists. It's also not meant for consuming content in-app - Pinchflat downloads content to disk where you can then watch it with a media center app or VLC.

If it doesn't work for your use case, please make a feature request! You can also check out these great alternatives: [Tube Archivist](https://github.com/tubearchivist/tubearchivist), [ytdl-sub](https://github.com/jmbannon/ytdl-sub), and [TubeSync](https://github.com/meeb/tubesync)

## Features

- Self-contained - just one Docker container with no external dependencies
- Powerful naming system so content is stored where and how you want it
- Easy-to-use web interface with presets to get you started right away
- First-class support for media center apps like Plex, Jellyfin, and Kodi ([docs](https://github.com/kieraneglin/pinchflat/wiki/Frequently-Asked-Questions#how-do-i-get-media-into-plexjellyfinkodi))
- Supports serving RSS feeds to your favourite podcast app ([docs](https://github.com/kieraneglin/pinchflat/wiki/Podcast-RSS-Feeds))
- Automatically downloads new content from channels and playlists
  - Uses a novel approach to download new content more quickly than other apps
- Supports downloading audio content
- Custom rules for handling YouTube Shorts and livestreams
- Apprise support for notifications
- Allows automatically redownloading new media after a set period
  - This can help improve the download quality of new content or improve SponsorBlock tags
- Optionally automatically delete old content ([docs](https://github.com/kieraneglin/pinchflat/wiki/Automatically-Delete-Media))
- Advanced options like setting cutoff dates and filtering by title ([docs](https://github.com/kieraneglin/pinchflat/wiki/Frequently-Asked-Questions#i-only-want-certain-videos-from-a-source---how-can-i-only-download-those))
- Reliable hands-off operation
- Can pass cookies to YouTube to download your private playlists ([docs](https://github.com/kieraneglin/pinchflat/wiki/YouTube-Cookies))
- Sponsorblock integration
- \[Advanced\] allows custom `yt-dlp` options ([docs](https://github.com/kieraneglin/pinchflat/wiki/%5BAdvanced%5D-Custom-yt%E2%80%90dlp-options))
- \[Advanced\] supports running custom scripts when after downloading/deleting media (alpha - [docs](https://github.com/kieraneglin/pinchflat/wiki/%5BAdvanced%5D-Custom-lifecycle-scripts))

## Screenshots

<img src="priv/static/images/app-form-screenshot.jpg" alt="Pinchflat screenshot" width="700" />
<img src="priv/static/images/app-screenshot.jpg" alt="Pinchflat screenshot" width="700" />

## Installation

### Unraid

Simply search for Pinchflat in the Community Apps store!

### Portainer

> [!IMPORTANT]  
> See the note below about storing config on a network file share. It's preferred to store the config on a local disk if at all possible.

Docker Compose file:

```yaml
version: '3'
services:
  pinchflat:
    image: ghcr.io/kieraneglin/pinchflat:latest
    environment:
      # Set the timezone to your local timezone
      - TZ=America/New_York
    ports:
      - '8945:8945'
    volumes:
      - /host/path/to/config:/config
      - /host/path/to/downloads:/downloads
```

### Docker

1. Create two directories on your host machine: one for storing config and one for storing downloaded media. Make sure they're both writable by the user running the Docker container.
2. Prepare the docker image in one of the two ways below:
   - **From GHCR:** `docker pull ghcr.io/kieraneglin/pinchflat:latest`
     - NOTE: also available on Docker Hub at `keglin/pinchflat:latest`
   - **Building locally:** `docker build . --file docker/selfhosted.Dockerfile -t ghcr.io/kieraneglin/pinchflat:latest`
3. Run the container:

```bash
# Be sure to replace /host/path/to/config and /host/path/to/downloads below with
# the paths to the directories you created in step 1
# Be sure to replace America/New_York with your local timezone
docker run \
  -e TZ=America/New_York \
  -p 8945:8945 \
  -v /host/path/to/config:/config \
  -v /host/path/to/downloads:/downloads \
  ghcr.io/kieraneglin/pinchflat:latest
```

### Podman

The Podman setup is similar to Docker but changes a few flags to run under a User Namespace instead of root. To run Pinchflat under Podman and use the current user's UID/GID for file access run this:

```
podman run \
  --security-opt label=disable \
  --userns=keep-id --user=$UID \
  -e TZ=America/Los_Angeles \
  -p 8945:8945 \
  -v /host/path/to/config:/config:rw \
  -v /host/path/to/downloads/:/downloads:rw \
  ghcr.io/kieraneglin/pinchflat:latest
```

Using this setup consider creating a new `pinchflat` user and giving that user ownership to the config and download directory. See [Podman --userns](https://docs.podman.io/en/v4.6.1/markdown/options/userns.container.html) docs.

### IMPORTANT: File permissions

You _must_ ensure the host directories you've mounted are writable by the user running the Docker container. If you get a permission error follow the steps it suggests. See [#106](https://github.com/kieraneglin/pinchflat/issues/106) for more.

> [!IMPORTANT]
> It's not recommended to run the container as root. Doing so can create permission issues if other apps need to work with the downloaded media.

### ADVANCED: Storing Pinchflat config directory on a network share

As pointed out in [#137](https://github.com/kieraneglin/pinchflat/issues/137), SQLite doesn't like being run in WAL mode on network shares. If you're running Pinchflat on a network share, you can disable WAL mode by setting the `JOURNAL_MODE` environment variable to `delete`. This will make Pinchflat run in rollback journal mode which is less performant but should work on network shares.

> [!CAUTION]
> Changing this setting from WAL to `delete` on an existing Pinchflat instance could, conceivably, result in data loss. Only change this setting if you know what you're doing, why this is important, and are okay with possible data loss or DB corruption. Backup your database first!

If you change this setting and it works well for you, please leave a comment on [#137](https://github.com/kieraneglin/pinchflat/issues/137)! Doubly so if it does _not_ work well.

### Environment variables

| Name                          | Required? | Default                   | Notes                                                                                                                                                                                                                    |
| ----------------------------- | --------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `TZ`                          | No        | `UTC`                     | Must follow IANA TZ format                                                                                                                                                                                               |
| `LOG_LEVEL`                   | No        | `debug`                   | Can be set to `info` but `debug` is strongly recommended                                                                                                                                                                 |
| `UMASK`                       | No        | `022`                     | Unraid users may want to set this to `000`                                                                                                                                                                               |
| `BASIC_AUTH_USERNAME`         | No        |                           | See [authentication docs](https://github.com/kieraneglin/pinchflat/wiki/Username-and-Password)                                                                                                                           |
| `BASIC_AUTH_PASSWORD`         | No        |                           | See [authentication docs](https://github.com/kieraneglin/pinchflat/wiki/Username-and-Password)                                                                                                                           |
| `EXPOSE_FEED_ENDPOINTS`       | No        | `false`                   | See [RSS feed docs](https://github.com/kieraneglin/pinchflat/wiki/Podcast-RSS-Feeds)                                                                                                                                     |
| `ENABLE_IPV6`                 | No        | `false`                   | Setting to _any_ non-blank value will enable IPv6                                                                                                                                                                        |
| `JOURNAL_MODE`                | No        | `wal`                     | Set to `delete` if your config directory is stored on a network share (not recommended)                                                                                                                                  |
| `TZ_DATA_DIR`                 | No        | `/etc/elixir_tzdata_data` | The container path where the timezone database is stored                                                                                                                                                                 |
| `BASE_ROUTE_PATH`             | No        | `/`                       | The base path for route generation. Useful when running behind certain reverse proxies - prefixes must be stripped.                                                                                                      |
| `YT_DLP_WORKER_CONCURRENCY`   | No        | `2`                       | The number of concurrent workers that use `yt-dlp` _per queue_. Set to 1 if you're getting IP limited, otherwise don't touch it                                                                                          |
| `ENABLE_PROMETHEUS`           | No        | `false`                   | Setting to _any_ non-blank value will enable Prometheus. See [docs](https://github.com/kieraneglin/pinchflat/wiki/Prometheus-and-Grafana)                                                                                |
| `ORPHANED_JOB_RESCUE_MINUTES` | No        | `120`                     | How long a job may sit `executing` before Oban assumes the node running it is gone and hands it back. Must exceed the longest download this instance can legitimately run, or a slow download is mistaken for a dead one |
| `SKIP_MIGRATION_BACKUP`       | No        |                           | Set to any non-blank value to migrate without copying the database first. The copy needs roughly as much free space as the database uses, so a full disk is the realistic reason to need this                            |

### Reverse Proxies

Pinchflat makes heavy use of websockets for real-time updates. If you're running Pinchflat behind a reverse proxy then you'll need to make sure it's configured to support websockets.

## EFF donations

Prior to 2024-05-10, a portion of all donations were given to the [Electronic Frontier Foundation](https://www.eff.org/). Now, the app doesn't accept donations that go to me personally and instead directs you straight to the EFF. [Here](https://github.com/kieraneglin/pinchflat/issues/234) are some people that have generously donated.

The EFF defends your online liberties and [backed](https://github.com/github/dmca/blob/9a85e0f021f7967af80e186b890776a50443f06c/2020/11/2020-11-16-RIAA-reversal-effletter.pdf) `youtube-dl` when Google took them down.

## Stability disclaimer

This software is in active development and anything can break at any time. I make no guarantees about the stability of this software, forward-compatibility of updates, or integrity (both related to and independent of Pinchflat).

## License

See `LICENSE` file

<!-- Images and links -->

[license-badge]: https://img.shields.io/github/license/kieraneglin/pinchflat?style=for-the-badge&color=ee512b
[license-badge-url]: LICENSE
