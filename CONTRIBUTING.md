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
   - Builds for Apple Silicon and Intel
   - Creates DMG files
   - Generates release notes
   - Publishes the release

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

## Questions?

Feel free to open an issue or reach out to the maintainer.
