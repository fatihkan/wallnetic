# Contributing to Wallnetic

Thank you for your interest in contributing to Wallnetic!

## Development Workflow

### Branches

| Branch | Purpose |
|--------|---------|
| `main` | Production-ready code, protected |
| `dev` | Development branch, integration testing |
| `feature/*` | New features |
| `fix/*` | Bug fixes |

### Branch Flow

```
feature/xyz ──┐
              ├──> dev ──> main ──> tag (v1.x.x) ──> Release
fix/abc ──────┘
```

### Getting Started

1. **Fork** the repository
2. **Clone** your fork
3. **Create** a new branch from `dev`:
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feature/your-feature-name
   ```

4. **Make** your changes
5. **Commit** with clear messages:
   ```bash
   git commit -m "feat: add new wallpaper transition effect"
   ```

6. **Push** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Open** a Pull Request to `dev` branch

### Commit Message Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/):

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation |
| `style` | Code style (formatting, etc.) |
| `refactor` | Code refactoring |
| `perf` | Performance improvement |
| `test` | Adding tests |
| `chore` | Maintenance tasks |

Examples:
```
feat: add multi-monitor wallpaper sync
fix: resolve memory leak in video renderer
docs: update installation instructions
```

## Release Process

Releases are automated via GitHub Actions:

1. **Merge** approved PRs to `dev`
2. **Test** thoroughly on `dev` branch
3. **Merge** `dev` to `main` when ready
4. **Create** a new tag:
   ```bash
   git checkout main
   git pull origin main
   git tag v1.x.x
   git push origin v1.x.x
   ```
5. **GitHub Actions** automatically:
   - Verifies the tag matches the committed version and preserves the build number
   - Builds for Apple Silicon and Intel
   - Verifies app/widget versions, architectures and signatures, then creates DMG files
   - Adds SHA-256 checksums
   - Generates release notes
   - Creates a draft release
6. **Verify and publish** the draft after CI succeeds: download both DMGs,
   check their checksums, mount them and confirm the app/widget versions and
   architectures. Direct downloads use ad-hoc signing and are not Apple-notarized;
   the App Store package uses a separate Apple distribution signature.

Add the release notes to `docs/releases/<version>.md` under
`## What's New — English` before tagging. The workflow uses this section for
the public GitHub release notes.

## Development Setup

### Requirements
- macOS 13.0+
- Xcode 15.0+
- Git

### Setup

```bash
# Clone the repository
git clone https://github.com/fatihkan/wallnetic.git
cd wallnetic

# Open in Xcode
open src/Wallnetic/Wallnetic.xcodeproj

# Build and run (⌘ + R)
```

## Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI for all new views
- Keep functions small and focused
- Add comments for complex logic

## Translations

Wallnetic's interface is translated into German, French, Japanese and
Simplified Chinese. The translations were made with AI assistance and are
open to revision: a correction from someone who speaks the language is the
best way they get better.

- **To report** a wrong, awkward, cut-off or untranslated text, open a
  [Translation Correction](https://github.com/fatihkan/wallnetic/issues/new?template=translation.md)
  issue. No code is needed.
- **To correct it yourself:**
  1. Open `src/Wallnetic/Resources/Localizable.xcstrings` in Xcode. Each
     language is a column; the English text is the key.
  2. Change the text. Keep every placeholder (`%@`, `%lld`, `%%`) and follow
     the terms in [docs/LOCALIZATION_GLOSSARY.md](docs/LOCALIZATION_GLOSSARY.md).
  3. Set the string's state to Reviewed if you are a native speaker and are
     sure of it.
  4. Open a pull request to `dev` and say which language you speak.
- The other places with text are listed in
  [docs/LOCALIZATION.md](docs/LOCALIZATION.md): the widget, the Photos
  permission text and the App Shortcuts phrases.
- **A new language** is welcome too. Open an issue first, so the work is not
  done twice.

## Questions?

Feel free to open an issue or reach out to the maintainer.
