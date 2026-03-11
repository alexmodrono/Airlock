# Releasing Airlock

This repository is structured to be pushed directly as a standalone GitHub repository.

## First Push

If the GitHub repository does not exist yet, create `amodrono/Airlock` on GitHub first, then:

```bash
git remote add origin git@github.com:amodrono/Airlock.git
git push -u origin main
```

If you prefer HTTPS:

```bash
git remote add origin https://github.com/amodrono/Airlock.git
git push -u origin main
```

## Continuous Integration

GitHub Actions runs the package checks defined in `.github/workflows/ci.yml`:

- `swift build`
- `swift test`
- `xcodebuild` for the demo app

## Cutting a Release

1. Make sure `main` is green in GitHub Actions.
2. Confirm the README examples still match the public API.
3. Create a semantic version tag:

```bash
git tag 1.0.0
git push origin 1.0.0
```

4. Create a GitHub Release from that tag.

## Notes

- Swift Package Manager expects semantic version tags.
- If you publish under a different GitHub owner, update the README package URL before release.
