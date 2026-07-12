# Fork maintenance guide

## Customizations that should be preserved intentionally

### Fork packaging and CI

- `Dockerfile` builds a small Alpine 3.22 daemon image. It enables the daemon,
  web client, NLS, inotify, OpenSSL, and uTP, disables desktop clients/tests,
  rebuilds the web assets, uses ccache, and installs `tzdata` in the runtime.
- `.dockerignore` limits the Docker build context.
- `.github/workflows/ci.yml` replaces upstream CI with a fork-specific,
  path-filtered build that publishes amd64 and arm64 images to
  `ghcr.io/ivanjx/transmission` from pushes to `mine`.
- The fork deletes upstream's `actions.yml`, `codeql.yml`,
  `update-copyright.yml`, and `webapp.yml`. During a merge, an upstream change
  that recreates or renames these workflows needs a deliberate keep/delete
  decision; do not resolve this area mechanically.
- `settings.json` is an opinionated container configuration for `/downloads`,
  `/incomplete`, `/config`, and an externally reachable RPC service. It also
  carries the fork-only settings described below. Treat changes to RPC bind,
  authentication, whitelist, and password values as security-sensitive.
- `CMakeLists.txt` sets `TR_VERSION_DEV` to `FALSE`, so fork builds identify as
  non-development builds. Recheck this whenever upstream changes versioning.

### Daemon and networking behavior

Two settings are additions to upstream's session settings API. Preserve all of
their plumbing together: constants/defaults, quark keys, legacy API aliases,
settings serialization, session accessors, implementation, and the sample
`settings.json` values.

1. `peer-limit-global-seeding` (default `200`) adds a separate session-wide
   peer cap for seeding torrents. `peer-mgr.cc` applies the limit both when
   selecting outbound candidates and when culling existing active upload
   peers. Its main conflict risk is upstream refactoring of peer candidate
   selection, peer accounting, or session limits.
2. `gateway-address` optionally supplies a forced IPv4 gateway to libnatpmp.
   It flows through `SessionSettings`, the port-forwarding mediator, and
   `tr_natpmp`, then calls `initnatpmp()` with the forced gateway. Non-IPv4 or
   invalid values fall back to normal discovery. Its main conflict risk is an
   upstream port-forwarding or libnatpmp API change.

Other daemon differences:

- `tr-dht.cc` logs every resolved DHT bootstrap address at debug level. This is
  diagnostic behavior, not the earlier multi-bootstrap-node experiment; only
  the debug log survives in the current patch.
- `api-compat.cc` accepts kebab-case legacy names for both fork-only settings.
  If upstream changes the fixed `SessionKeys` array, recalculate its size and
  retain both mappings.

### Web client behavior

The source-of-truth web changes live in `web/src/` and
`web/assets/css/transmission-app.scss`:

- Storage and traffic totals use 1024-based units. `Formatter.size()` was
  changed and a separate `Formatter.bandwidth()` formatter was added for
  statistics.
- Torrent text search also matches the download directory.
- The add-torrent destination input offers up to 100 unique existing download
  directories through a datalist.
- Display options expose a persisted refresh interval from 1 to 30 seconds.
- Torrent filters include low, normal, and high bandwidth priority.
- Changing the priority of all files in a single torrent also updates that
  torrent's `bandwidth_priority` RPC field.
- Peer inspection adds a country column. It looks up each peer IP with
  `https://api.country.is/`, caches successful country codes in memory, and
  loads flag images from `https://flagcdn.com`. This introduces external
  browser requests and has privacy, availability, CSP, and HTML-injection
  implications; reassess it if upstream changes web security policy.
- Peer/webseed column sizing is customized for compact and small viewports.
- Additional surviving UI tweaks include webseed display adjustments and
  supporting helpers such as `setHTMLContent()`.

`web/public_html/transmission-app.js`, `.css`, and `.css.map` are compiled
outputs corresponding to those source changes. **Do not hand-edit them.** After
resolving web source conflicts, use the web build process installed by the
current upstream version and commit regenerated outputs together. Several
historical commits named `Update web builds` or `Update web assets` exist only
to synchronize these generated files.

Some older fork work no longer appears in the surviving diff (for example the
Clusterize list virtualization experiment and multiple DHT bootstrap nodes).
Do not resurrect a feature based only on an old commit message; verify it is
present in `git diff upstream/main...mine` first.

## Files most likely to conflict

| Area | Important paths | Resolution principle |
| --- | --- | --- |
| Settings schema | `constants.h`, `quark.h/.cc`, `api-compat.cc`, `session-settings.h`, `session.h` | Port the two settings into upstream's current schema instead of blindly accepting either side. |
| Peer management | `peer-mgr.cc` | Preserve upstream scheduling/accounting fixes, then reapply the separate seeding cap using current peer semantics. |
| NAT-PMP | `port-forwarding*.h/.cc`, `port-forwarding-natpmp.h/.cc`, `session.h` | Preserve the optional forced gateway end to end and confirm the installed libnatpmp signature. |
| Web model/filtering | `torrent.js`, `transmission.js`, `prefs.js` | Keep upstream field naming/event flow while retaining directory search and priority filters. |
| Web inspector | `inspector.js`, `transmission-app.scss` | Reconcile upstream table/layout/security changes before restoring country flags and priority propagation. |
| Packaging/automation | `Dockerfile`, `.dockerignore`, `.github/workflows/` | These are deployment policy, so resolve according to the fork's intended image and CI behavior. |
| Generated web assets | `web/public_html/transmission-app.*` | Never merge minified bundles by hand; rebuild them from resolved source. |

## Recommended upstream merge procedure

1. Start clean, fetch both remotes, and record the exact refs:

   ```sh
   git status --short --branch
   git fetch upstream main --prune
   git fetch origin mine --prune
   git rev-parse mine upstream/main
   git merge-base mine upstream/main
   ```

2. Review upstream-only work and the surviving fork patch separately:

   ```sh
   git log --oneline mine..upstream/main
   git diff --stat upstream/main...mine
   git diff upstream/main...mine -- libtransmission web/src web/assets Dockerfile .github settings.json
   ```

3. Predict conflicts without touching the branch:

   ```sh
   git merge-tree --write-tree mine upstream/main
   ```

4. Merge `upstream/main` into `mine`. For conflicts, use this document as an
   intent guide, but use upstream's current architecture and installed
   dependency versions as the implementation source of truth.
5. Regenerate web bundles if any web source, style, or build dependency changed.
6. Run targeted formatting, lint, compilation, and tests for every affected
   area. At minimum, validate settings round-tripping and legacy aliases, both
   peer-limit paths, NAT-PMP with and without a forced gateway, web filtering
   and priority RPC behavior, and the multi-architecture container build.
7. Re-run the triple-dot diff and update this document if a customization was
   added, removed, renamed, or intentionally superseded upstream.

## Reading the history safely

Use `git log --first-parent mine` to understand the sequence of upstream merges
and fork integration points. Use path-limited, no-merge history to investigate
the rationale behind a current customization:

```sh
git log --no-merges --oneline upstream/main...mine -- libtransmission/peer-mgr.cc
git log --no-merges --oneline upstream/main...mine -- web/src/inspector.js
```

The first-parent history shows that the fork has repeatedly merged upstream
rather than rebasing. Continue that convention unless the owner explicitly
chooses to rewrite history.
