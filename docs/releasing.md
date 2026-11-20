# Releasing

Releases are built and published by GitHub Actions from a tag. Nothing is uploaded from a developer machine, and the workflow refuses to overwrite an existing release.

## What a release contains

| Asset | Contents |
| --- | --- |
| `Glint-<version>-macos-universal.zip` | `Glint.app`, universal (`arm64` + `x86_64`), ad-hoc signed |
| `SHA256SUMS.txt` | Checksum of the archive |

## Steps

1. **Bump the version** in `project.yml`: set `MARKETING_VERSION` to the new `MAJOR.MINOR.PATCH` and add one to `CURRENT_PROJECT_VERSION`. The app, the update checker and `--version`-style displays read these.
2. **Write the release notes** at `docs/releases/v<version>.md`. The workflow publishes this file verbatim as the release body, and the website's changelog renders it too. It has to make sense to someone who has never seen the repository.
3. **Check locally** before tagging:

   ```bash
   ./scripts/validate-release.sh v1.1.0
   ```

   It prints the version on success. Otherwise it says what disagrees: a malformed tag, a version that doesn't match `project.yml`, a non-integer build number, or missing release notes.
4. **Dry-run the packaging** (optional). Run the *Release macOS app* workflow with `workflow_dispatch`, giving the intended tag and the ref to package (a branch name or a full 40-character SHA). It builds, verifies and uploads the assets as a workflow artifact without publishing anything.
5. **Tag and push**:

   ```bash
   git tag -a v1.1.0 -m "Glint 1.1.0"
   git push origin v1.1.0
   ```

   The workflow validates, runs the engine tests, builds the universal app and verifies it. It then archives it, re-checks the archive in a clean directory and publishes the release with the notes.

## Signing and Accessibility

Releases are ad-hoc signed. macOS keys the Accessibility permission to the signature, so users re-enable Glint in **Privacy & Security → Accessibility** after each update. The release notes and the website say so. For local development, `./scripts/build-app.sh --dev-sign` signs with the Apple Development identity in `project.yml`, so the permission survives rebuilds.
