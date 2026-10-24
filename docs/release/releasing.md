# Releasing

Releases are built by CI from a tag. There's no version commit: the tag is
the version.

## Cutting a release

1. Make sure `main` is green in CI.
2. Tag the commit on `main` and push the tag:

       git tag -a v0.9.2 -m "IONFALL 0.9.2"
       git push origin v0.9.2

   `v1.0` means 1.0.0. A suffix such as `v1.0.0-rc2` makes a pre-release of
   1.0.0.
3. CI (`.github/workflows/ci.yml`) runs the tests, builds every platform with
   that version (and the matching Android versionCode), smoke-tests the
   exported game as a server (`--server`) on every map and mode, and creates a **draft** release
   with:
   - `ionfall-<version>-{linux,windows,web}.zip`
   - `ionfall-<version>-android-arm64.apk` and `ionfall-<version>.aab`
     (only when the Android upload key secrets are set, see below)
   - `SHA256SUMS`

   The notes start from `docs/release/notes-template.md` plus GitHub's list
   of merged pull requests.
4. Open the draft on the Releases page, write the "What's new" section and
   **Publish**.
5. Publishing deploys GitHub Pages (`.github/workflows/pages.yml`): the
   browser game at `/play/` becomes the new web build and the landing page's
   download links point at the new files. The README links to the latest
   release, so nothing needs editing.

Re-running CI on the same tag replaces the draft's files.

## One-time setup: Android signing in CI

Without these secrets a tag's release has no APK or Play bundle (CI warns).
They're the Play **upload key** from `~/.local/share/ionfall-keys/`; set
them yourself (never commit them):

    gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64 < <(base64 -w0 ~/.local/share/ionfall-keys/ionfall-upload.jks)
    gh secret set ANDROID_UPLOAD_KEY_ALIAS      # the GODOT_ANDROID_KEYSTORE_RELEASE_USER value
    gh secret set ANDROID_UPLOAD_KEY_PASSWORD   # the GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD value

The EOS secrets (online play) are already set.

## Building by hand

`tools/package_release.sh` (desktop and servers) and
`tools/android_release.sh` (signed AAB) still build locally from
`project.godot`'s version, for testing a build before tagging.
