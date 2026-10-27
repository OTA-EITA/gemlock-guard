# gemlock-guard

[![ci](https://github.com/OTA-EITA/gemlock-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/OTA-EITA/gemlock-guard/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/OTA-EITA/gemlock-guard/badge)](https://securityscorecards.dev/viewer/?uri=github.com/OTA-EITA/gemlock-guard)

**Supply-chain checks for Ruby projects that `bundler-audit` doesn't do.**

[bundler-audit](https://github.com/rubysec/bundler-audit) knows about published advisories in the Ruby Advisory Database. gemlock-guard looks at the things that let a _not-yet-known_ attack in: versions released a few days ago, gem sources that can stand in for each other, git gems that follow a branch, lockfile entries without a checksum and names one typo away from a popular gem. It reads `Gemfile`, `Gemfile.lock` and `.bundle/config` as text — nothing is evaluated, no dependencies, plain Ruby — and only talks to rubygems.org when you pass `--online`.

```text
$ exe/gemlock-guard --online test/fixtures/risky
test/fixtures/risky/.bundle/config:2  HIGH   GG007  BUNDLE_SSL_VERIFY_MODE is 0: Bundler does not verify TLS certificates
test/fixtures/risky/.bundle/config:3  HIGH   GG007  BUNDLE_DISABLE_CHECKSUM_VALIDATION is true: gems are installed even when their checksum does not match
test/fixtures/risky/Gemfile.lock:9  HIGH   GG001  legacy-tools from git://github.com/acme/legacy-tools.git is fetched over the unauthenticated git:// protocol
test/fixtures/risky/Gemfile.lock:22  HIGH   GG001  remote http://gems.acme.internal/ (5 gem(s)) is fetched over plain HTTP
test/fixtures/risky/Gemfile.lock:25  HIGH   GG006  prism@2.0.0 was released 3 day(s) ago and builds a native extension, which runs code during install
test/fixtures/risky/Gemfile:4  MEDIUM GG002  the Gemfile has 2 global sources: any of them may supply any gem
test/fixtures/risky/Gemfile.lock:1  MEDIUM GG003  acme-payments from https://github.com/acme/acme-payments.git tracks branch main: `bundle update` installs whatever was pushed last
test/fixtures/risky/Gemfile.lock:15  MEDIUM GG004  acme-core is loaded from /srv/gems/acme-core, outside this repository
test/fixtures/risky/Gemfile.lock:20  MEDIUM GG002  one GEM section has 2 remotes (https://rubygems.org/, http://gems.acme.internal/): Bundler may take any of its gems from any of them
test/fixtures/risky/Gemfile.lock:24  MEDIUM GG008  nokogirl looks like a typo of the popular gem nokogiri
test/fixtures/risky/Gemfile.lock:27  MEDIUM GG005  rspec-mokcs-3.13.0 is missing from the CHECKSUMS section
test/fixtures/risky/Gemfile.lock:27  MEDIUM GG008  rspec-mokcs looks like a typo of the popular gem rspec-mocks
test/fixtures/risky/Gemfile.lock:28  MEDIUM GG006  rubocop@1.92.1 was released 2 day(s) ago
test/fixtures/risky/Gemfile.lock:47  MEDIUM GG005  nokogirl-1.0.0 has an empty CHECKSUMS entry
test/fixtures/risky/Gemfile.lock:8  LOW    GG003  legacy-tools from git://github.com/acme/legacy-tools.git follows tag v1.2.0, which can be moved

1 project(s), 15 finding(s): 5 high, 9 medium, 1 low
```

(Run on 2026-10-25. `prism` 2.0.0 and `rubocop` 1.92.1 are real releases from that week, which is why they show up.)

## Why check release age when Bundler has a cooldown

Bundler 4.0.13 added a `cooldown` setting ([rubygems#9576](https://github.com/ruby/rubygems/pull/9576)): `source "https://rubygems.org", cooldown: 7` in the Gemfile, `bundle config set cooldown 7`, or `--cooldown 7` on `install`, `update`, `lock` and friends. Use it — this repository does. It has three gaps that a check in CI covers:

- **It is off unless you turn it on**, and only Bundler 4.0.13 and later understand it.
- **It never touches versions already in the lockfile.** Cooldown decides what the resolver may _adopt_; a version that is already locked stays, by design ([rubygems#9619](https://github.com/ruby/rubygems/pull/9619)). A `Gemfile.lock` written by a teammate without the setting, by an older Bundler or by a bot goes through `bundle install` unchecked.
- **It trusts the gem server's metadata.** Versions without a `created_at` in the compact index — older servers, private registries, historical entries — are treated as old enough ([`bundle config` docs](https://github.com/ruby/rubygems/blob/master/lib/bundler/man/bundle-config.1.ronn)).

Most hijacked releases are found and yanked within days. gemlock-guard looks up each locked version's `created_at` on rubygems.org and reports the ones younger than `--min-age` days, whoever wrote the lockfile. It downloads the few fresh `.gem` files to see whether the plain `ruby` variant builds a native extension or ships a RubyGems plugin: both run code during `bundle install`, so those are high.

When something is too fresh, hold it back:

```sh
bundle update rubocop --cooldown 7   # Bundler 4.0.15+: gems named on the command line are subject to cooldown again
```

## Checks

| ID    | Severity | What it finds                                                                                                                                                                                                                                                                                         |
| ----- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GG001 | high     | Gem sources and git gems fetched over `http://` or `git://` (from the lockfile; from the Gemfile when there is no lockfile)                                                                                                                                                                           |
| GG002 | medium   | More than one global `source` in the Gemfile, or a lockfile `GEM` section with several `remote:` lines: any of the sources may supply any gem. Bundler deprecated this in 1.13 and removed it in 4.0 ([rubygems#8968](https://github.com/ruby/rubygems/pull/8968)); Bundler 2 lockfiles still have it |
| GG003 | medium   | Git gems that follow a branch (the default one, `branch:` or a non-SHA `ref:`), so `bundle update` takes whatever was pushed last; **low** for `tag:` and abbreviated SHAs. A full commit SHA in `ref:` is fine                                                                                       |
| GG004 | medium   | `path:` gems outside the repository (absolute paths, `../` beyond the git work tree)                                                                                                                                                                                                                  |
| GG005 | medium   | The lockfile has a `CHECKSUMS` section, but a gem from a registry is missing from it or has an empty entry. A lockfile without `CHECKSUMS` is not a finding: it is opt-in before Bundler 4.0                                                                                                          |
| GG006 | medium   | `--online`: versions released less than `--min-age` days ago (default 7); **high** when the gem builds a native extension or ships a RubyGems plugin                                                                                                                                                  |
| GG007 | high     | `.bundle/config` with `BUNDLE_SSL_VERIFY_MODE: "0"` (no TLS certificate checks) or `BUNDLE_DISABLE_CHECKSUM_VALIDATION: "true"`                                                                                                                                                                       |
| GG008 | medium   | Names one typo away from a popular gem (`nokogirl`, `rspec-mokcs`, `rest_client`)                                                                                                                                                                                                                     |

Notes on the sources the checks rest on:

- The lockfile is read the way Bundler's [`LockfileParser`](https://github.com/ruby/rubygems/blob/master/lib/bundler/lockfile_parser.rb) splits it. `CHECKSUMS` appeared in Bundler 2.5; `bundle lock --add-checksums` and the `lockfile_checksums` setting came in 2.6.0, and 4.0 turned it on for new lockfiles ([rubygems#8981](https://github.com/ruby/rubygems/pull/8981)). Git and path gems are listed without a checksum by design, so only registry gems are checked. Bundler itself refuses a frozen install with a missing entry since 2.6.7 and with an empty one since 2.7.2 — gemlock-guard tells you before that, and on older Bundlers that don't.
- rubygems.org already rejects new gem names that differ from a popular gem only in case, `-` or `_` ([`GemTypo`](https://github.com/rubygems/rubygems.org/blob/master/app/models/gem_typo.rb)). GG008 also catches one-letter edits and swapped letters (optimal string alignment distance 1), and separator variants on other registries. Names shorter than five letters, and pairs that differ only by a trailing number (`oauth`/`oauth2`), are skipped: they have too many legitimate neighbours.
- `bundler-audit` also reports `http://` and `git://` sources. GG001 overlaps with that on purpose, so the check is there for projects that don't run it; everything else here is not in `bundler-audit`, and gemlock-guard does not look at advisories at all. Run both.

## Tested on real projects

| Project                                                                     | Locked gems | Gemfiles scanned | Findings with `--online`                                                                                                                              |
| --------------------------------------------------------------------------- | ----------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| [mastodon/mastodon](https://github.com/mastodon/mastodon) (f045f6b)         | 345         | 1                | 11 versions released 2–4 days earlier (aws-sdk-\*, crass, excon, kaminari-\*)                                                                         |
| [discourse/discourse](https://github.com/discourse/discourse) (568a006)     | 299         | 2                | 1 git gem on its default branch (raindrops), 3 versions released 3–4 days earlier                                                                     |
| [forem/forem](https://github.com/forem/forem) (88f91b4)                     | 420         | 1                | 1 git gem on branch `master` (acts_as_follower)                                                                                                       |
| [rails/rails](https://github.com/rails/rails) (c4f04bd)                     | 233         | 2                | none                                                                                                                                                  |
| [rubygems/rubygems.org](https://github.com/rubygems/rubygems.org) (6c4b4bd) | 299         | 1                | 2 versions released 5 days earlier (aws-sdk-core, aws-sdk-kms)                                                                                        |
| [gitlabhq/gitlabhq](https://github.com/gitlabhq/gitlabhq) (d7b9a61)         | 774         | 33               | 1 version released 4 days earlier whose `ruby` variant builds a native extension (gitlab_query_language 0.42.0, high), 1 more released 5 days earlier |

Checked on 2026-10-25. "Locked gems" counts the root `Gemfile.lock`; "Gemfiles scanned" is every Gemfile below the root, with `vendor/` and test fixtures skipped (gitlabhq has 44 lockfiles, 11 of them under `vendor/gems` or `spec/fixtures`). Without `--online` the only findings are the two git gems. Mastodon's git gem is pinned with a full SHA in `ref:` and is correctly not reported. The first runs flagged `crack`, `ffaker`, `net-http2` and `omniauth-oauth` as typosquats; the rules above were tightened until they no longer do.

## Usage

```sh
git clone https://github.com/OTA-EITA/gemlock-guard
gemlock-guard/exe/gemlock-guard path/to/app              # one project, offline
gemlock-guard/exe/gemlock-guard --online path/to/app     # also check release ages on rubygems.org
gemlock-guard/exe/gemlock-guard packages/                # every Gemfile below a directory (monorepos)
```

It has no dependencies, so the script runs straight from the checkout with any Ruby 3.2 or later. In CI, use the GitHub Action below.

| Option            | Default  |                                                                           |
| ----------------- | -------- | ------------------------------------------------------------------------- |
| `--online`        | off      | Query rubygems.org for release dates (GG006)                              |
| `--min-age`       | `7`      | With `--online`, report versions released fewer than this many days ago   |
| `--format`        | `text`   | `text`, `json`, `markdown` or `sarif`                                     |
| `--fail-on`       | `medium` | Exit 1 on findings at least this severe (`high`, `medium`, `low`, `none`) |
| `--sarif-file`    |          | Also write a SARIF report to this file                                    |
| `--markdown-file` |          | Also write a Markdown report to this file                                 |
| `--list-checks`   |          | Print the checks                                                          |

`--online` asks `GET /api/v1/versions/<gem>.json` once per gem from rubygems.org, at most 8 requests a second (the [documented limit](https://guides.rubygems.org/rubygems-org-rate-limits/) is 10), retrying 429 and 5xx with backoff and honouring `Retry-After`. Gems from other sources are not queried. If rubygems.org cannot be reached, GG006 is skipped with a warning on stderr and the other checks still run.

### GitHub Actions

```yaml
permissions:
  contents: read
  security-events: write
steps:
  - uses: actions/checkout@v5
    with:
      persist-credentials: false
  - uses: OTA-EITA/gemlock-guard@v0.1.0 # pin to a commit SHA in real use
    id: guard
    with:
      online: "true"
      fail-on: high
  - uses: github/codeql-action/upload-sarif@v4
    if: always()
    with:
      sarif_file: ${{ steps.guard.outputs.sarif-file }}
      category: gemlock-guard
```

The action runs on the Ruby that GitHub's Ubuntu runners already have, with nothing to install, and makes a single pass that writes the SARIF report and the job summary. Run it before `bundle install`, together with `bundle-audit check --update`.

## Development

```sh
bundle install
bundle exec rake   # Minitest with SimpleCov thresholds, then RuboCop
```

Tests use Minitest: it ships with Ruby, and the same plain assertion style as the PHPUnit and Vitest suites of the sibling projects. The dev dependencies are locked to versions released at least 7 days ago — the Gemfile sets `cooldown: 7`, CI installs with `BUNDLE_FROZEN`, and gemlock-guard checks this repository's own lockfile with `--online` in CI.

## Related

- [lockfile-guard](https://github.com/OTA-EITA/lockfile-guard): the same idea for `package-lock.json`
- [composer-guard](https://github.com/OTA-EITA/composer-guard): the same idea for `composer.json` and `composer.lock`

## License

MIT
