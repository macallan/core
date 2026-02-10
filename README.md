# Core

A Ruby CLI tool to help speed up and improve the quality of code reviews by quickly identifying GitHub PRs that need your attention.

## Goals
- Make reviewing code more fun
- Make code reviewing faster
- Use the tool for all code reviews

## Features
- Lists PRs where you're assigned as a reviewer
- Lists PRs where you're assigned
- Tracks PRs from specific authors you follow
- Tracks recent activity on PRs since your last check
- Shows CI status, author, and age for each PR
- **Generates markdown context files for PRs** - Save notes and context for PRs you're reviewing
- Interactive arrow-key menu when run with no arguments
- Colored output and loading spinners during slow operations
- Uses `gh` CLI for GitHub API access

## Prerequisites

1. **Ruby**: Version 3.0 or higher (3.4+ recommended)
   ```bash
   brew install rbenv
   rbenv install 3.4.3
   ```
2. **GitHub CLI**: Install from https://cli.github.com/
   ```bash
   brew install gh
   ```
3. **Authenticate with GitHub**:
   ```bash
   gh auth login
   ```

## Installation

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd core
   ```

2. Install gem dependencies:
   ```bash
   bundle install
   ```

   If you use multiple Ruby versions via rbenv, install the gems for each version you'll run `core` under:
   ```bash
   RBENV_VERSION=3.4.2 gem install tty-prompt tty-spinner pastel
   RBENV_VERSION=3.4.3 gem install tty-prompt tty-spinner pastel
   ```

   > **Note**: The interactive UI (colors, spinners, menus) requires these gems. If they're not available, `core` still works — it falls back to plain text output.

3. Make the CLI executable:
   ```bash
   chmod +x bin/core
   ```

4. (Optional) Add to your PATH or symlink:
   ```bash
   # Symlink (recommended — stays up to date with git pulls)
   sudo ln -sf "$(pwd)/bin/core" /usr/local/bin/core

   # Or add to ~/.zshrc or ~/.bashrc
   export PATH="$PATH:/path/to/core/bin"
   ```

## Usage

### Add repositories to track

```bash
./bin/core --add-repo owner/repo
```

Example:
```bash
./bin/core --add-repo anthropics/claude-code
./bin/core --add-repo rails/rails
```

### Manage repositories

```bash
# List tracked repositories
./bin/core --list-repos

# Remove a repository
./bin/core --remove-repo owner/repo
```

### Track specific authors

Track PRs from specific authors. These PRs will always appear in your list, even if you're not assigned or requested as a reviewer.

```bash
# Add an author to track
./bin/core --add-author username

# List tracked authors
./bin/core --list-authors

# Remove a tracked author
./bin/core --remove-author username
```

Example:
```bash
./bin/core --add-author alice
./bin/core --add-author bob
```

Tracked authors are marked with a `*` in the output.

### PR Context Management

Generate and save markdown files with PR context, including metadata, description, files changed, CI status, and review comments. This helps you remember what a PR is about and track your review notes across multiple sessions.

#### Generate a context file for a PR

```bash
# From within a git repository (auto-detects repo)
./bin/core --context PR_NUMBER

# Specify repository explicitly
./bin/core --context PR_NUMBER --repo owner/repo
```

Examples:
```bash
./bin/core --context 123 --repo rails/rails
./bin/core --context 456 --repo anthropics/claude-code
```

Context files are saved to `~/.core/contexts/{owner}/{repo}/PR-{number}.md`

The generated file includes:
- PR title, author, status, and dates
- Full description
- List of files changed with line counts
- CI status and checks
- Recent review comments
- Personal notes section (preserved when regenerating)

Example context file:
```markdown
# PR #50000: ActiveRecord::Relation#order supports hash like where

**Repository**: rails/rails
**Author**: @mylesboone
**Status**: closed (Draft: false)
**Created**: 2023-11-10 13:08:53
**Updated**: 2024-04-10 19:57:36
**URL**: https://github.com/rails/rails/pull/50000

## Description

This PR enables a hash-style interface for order(), similar to where().
Allows: `Topic.includes(:posts).order(posts: { created_at: :desc })`

## Files Changed (4 files)

- activerecord/CHANGELOG.md [modified] (+8, -0)
- activerecord/lib/active_record/relation/query_methods.rb [modified] (+29, -15)
- activerecord/test/cases/relation/order_test.rb [added] (+65, -0)
- guides/source/active_record_querying.md [modified] (+8, -0)

## CI Status

_No CI checks configured_

## Review Comments (2 comments)

**@rafaelfranca** (2024-02-20 23:33:10):
We should not use `e.class` here...

---

## My Review Notes

<!-- Add your notes below -->

### First Review - 2026-01-26

Nice feature, maintains backward compatibility.
```

#### List saved context files

```bash
# List all contexts
./bin/core --list-contexts

# List contexts for a specific repository
./bin/core --list-contexts owner/repo
```

#### View or edit context files

Context files are plain markdown and can be opened in any text editor:

```bash
# View with cat, bat, or your preferred viewer
cat ~/.core/contexts/rails/rails/PR-123.md

# Edit with your editor
vim ~/.core/contexts/rails/rails/PR-123.md

# Or set $EDITOR to auto-open after generation
export EDITOR=vim
./bin/core --context 123 --repo rails/rails
```

#### Updating context files

When you regenerate a context file, the PR metadata is refreshed but your personal notes are preserved:

```bash
# Add some notes manually to the "My Review Notes" section
vim ~/.core/contexts/rails/rails/PR-123.md

# Regenerate to get updated PR data (new commits, CI status, etc.)
./bin/core --context 123 --repo rails/rails

# Your notes are still there!
```

### List PRs needing attention

```bash
./bin/core list
```

This will show:
- PRs where you're requested as a reviewer
- PRs where you're assigned
- PRs from tracked authors
- PRs with activity since your last check

Example output:
```
PRs needing attention:

anthropics/claude-code
  #123  [✓ CI] Fix authentication bug            @alice*   2 days ago
  #124  [✗ CI] Add new feature                   @bob      5 hours ago

rails/rails
  #456  [⋯ CI] Refactor database layer           @charlie  1 week ago

Total: 3 PRs
* = Tracked author
```

### Refresh and ignore last check timestamp

```bash
./bin/core list --refresh
```

This shows all PRs where you're assigned or requested, regardless of recent activity.

### Get help

```bash
./bin/core --help
```

## Configuration

Configuration is stored in `~/.core.yml`:

```yaml
repos:
  - owner/repo1
  - owner/repo2
authors:
  - alice
  - bob
last_checked:
  owner/repo1: 2026-01-25T10:30:00Z
  owner/repo2: 2026-01-25T09:15:00Z
```

You can edit this file directly to:
- Add/remove repositories
- Add/remove tracked authors
- Reset timestamps (delete the `last_checked` entry for a repo)

### Storage Locations

- **Configuration**: `~/.core.yml`
- **PR Contexts**: `~/.core/contexts/{owner}/{repo}/PR-{number}.md`

Context files are organized by repository and can be backed up, versioned, or synced as needed.

## CI Status Icons

- `✓` - CI passing
- `✗` - CI failing
- `⋯` - CI pending
- ` ` - CI status unknown

## Technology

- **Language**: Ruby 3.0+
- **GitHub API**: Uses `gh` CLI for authenticated API access
- **Config**: YAML format stored in `~/.core.yml`
- **Gem dependencies**: `tty-prompt` (interactive menus), `tty-spinner` (loading indicators), `pastel` (ANSI colors)
- **Stdlib**: json, yaml, optparse, time, fileutils, open3

## Future Enhancements

- Automatically select the next PR to review
- Open PR in browser from CLI
- Support for GitLab
- PR priority scoring based on age, CI status, and team activity
- Auto-generate context when listing PRs (show ✓ indicator if context exists)
- Search contexts by keyword: `core --search-contexts "authentication"`
- Show inline diffs in context files
- Template customization for context files
- Export contexts to PDF or HTML
