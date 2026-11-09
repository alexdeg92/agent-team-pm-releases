# CI, versioned releases and release notes (mandatory for every team)

These rules apply to every project a team builds or changes, whether or not the
user asks. Left alone, agents test by hand, merge on "works on my machine",
deploy by copying files and forget to tell anyone what changed. The PM sets up
the pipeline before feature work, and the critic blocks any branch that skips it.

## Before the first feature
- CI runs on every pull request: lint, format check, typecheck, unit and
  integration tests, the architecture boundary check, a build, and a migration
  test on a seeded database when there is one. It is the same commands a
  developer runs locally, through one entry point (`make check` or a package
  script).
- The checks are required on the base branch. Nobody merges red, and nobody
  pushes to the base or release branch directly.
- CI is fast enough to run on every push: cache dependencies, run sides in
  parallel, and run only the affected suites on pull requests. The full suite
  runs on the release candidate.

## Branches and releases
- One integration branch (`main`) that is always releasable and is where the
  user tests. Work reaches it only by reviewed pull request.
- Production gets a release: a pull request or tag from the integration branch,
  never a hand-picked set of commits and never a manual copy to the server.
- The full suite (end-to-end included) must pass on the exact commit being
  released. A green run on an older commit does not count.
- Every release gets a version, assigned automatically when it is cut: calendar
  (`v2026.11.09`, with a suffix for a second release that day) or semver,
  chosen once and written in the architecture doc. The version is a git tag and
  is visible in the running app and its health endpoint.

## Release notes
- Every pull request with a user-visible change adds a change note in the same
  branch, as its own small file (for example `changes/<branch>.md`), so notes
  never conflict. Internal-only changes are marked as such.
- A note is written for the people who use the product: what they can now do or
  what was fixed, in their words and in every language the UI ships, no code
  names or ticket jargon.
- CI fails a pull request that changes user-facing code without a note.
- Cutting a release gathers the notes into the release (changelog entry, GitHub
  release, in-app "what's new") and clears them. Compare the merged pull
  requests against the notes before publishing.

## Deploy
- Deploys are automated from the release: build once, deploy that same artifact,
  with no manual steps on the server.
- Before any schema change reaches production, the pipeline takes a backup and
  checks it can be read. Migrations run as part of the deploy.
- After the deploy, the pipeline checks health, the version served and a smoke
  test of the main API flows, and rolls back automatically if they fail. The
  rollback command is written down and tested.
- Secrets live in the CI and server secret stores, never in the repo or logs.

## Review gate
The critic checks every branch against this file. A missing or failing required
check, a user-visible change without a note, a release without a green full
suite on its exact commit, or a manual deploy step is a NO-GO (P2 or higher).

## Rules block for briefs
Paste this into the shared brief and every builder brief:

```text
CI and release rules (mandatory):
- Run the project's check command before every report; CI must be green, no
  merging red, no direct pushes to main or the release branch.
- Every user-visible change adds a change note file in the same branch, in the
  users' words and every UI language. Internal changes are marked internal.
- Releases are cut from main with an automatic version tag, the full suite green
  on that exact commit, and notes gathered from the change files.
- Deploys are automated: backup before migrations, health and smoke check after,
  automatic rollback. No manual steps on the server.
```
