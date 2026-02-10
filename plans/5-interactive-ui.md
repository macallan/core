# Implementation Plan: Interactive UI with Colors, Spinners, and Menus

## Overview

Add a polished terminal UI to the CLI using TTY toolkit gems. The CLI previously used plain `puts` for all output with no loading indicators during slow API/git operations (2-15s), no colors, and no interactive menus.

**Problem**: Running `core` with no args silently fetches PRs with a single status message. There's no visual feedback during slow operations and no way to discover commands without reading `--help`.

**Goal**: Make the CLI feel responsive and professional with colored output, spinners during slow operations, and an interactive arrow-key menu when invoked with no arguments.

## Key Decisions

- **Three TTY gems**: `tty-prompt` (interactive menus), `tty-spinner` (loading indicators), `pastel` (ANSI colors)
- **Centralized UI module**: All TTY gem usage goes through `lib/core/ui.rb` — no other file requires gems directly
- **Graceful degradation**: Gems are lazy-loaded with `rescue LoadError`. If unavailable (wrong Ruby version, no bundle), everything falls back to plain text
- **Bundler is optional**: `bin/core` wraps `require 'bundler/setup'` in begin/rescue so the CLI works without `bundle exec`
- **Interactive mode is additive**: Only activates when `command == nil && $stdin.tty? && gems_available?`. Piped/non-TTY input falls back to `list_prs`
- **Colors applied after padding**: ANSI escape codes break `ljust` alignment, so all padding happens on plain strings first

## Dependencies Added

```ruby
# Gemfile
source 'https://rubygems.org'
ruby '>= 3.0'
gem 'tty-prompt', '~> 0.23'
gem 'tty-spinner', '~> 0.9'
gem 'pastel', '~> 0.8'
```

Gems must be installed for each Ruby version used: `RBENV_VERSION=3.4.2 gem install tty-prompt tty-spinner pastel`

## Files Created

### `.ruby-version`
Pins Ruby 3.4.3 for the project directory.

### `Gemfile`
Declares the three TTY gem dependencies.

### `lib/core/ui.rb` (~120 lines)

Centralized UI facade. No other file requires TTY gems directly.

**Gem loading** — lazy with fallback:
```ruby
GEMS_AVAILABLE = begin
  require 'pastel'
  require 'tty-spinner'
  require 'tty-prompt'
  true
rescue LoadError
  false
end
```

**Color helpers** (return plain text when gems unavailable):
- `UI.success(text)` → green
- `UI.error(text)` → red
- `UI.dim(text)` → dim gray
- `UI.bold(text)` → bold
- `UI.warning(text)` → yellow
- `UI.ci_icon(status)` → colored ✓/✗/⋯

**Output helpers** (replace raw `puts` patterns):
- `UI.say_ok(text)` → green "✓ text"
- `UI.say_error(text)` → red "Error: text" to stderr
- `UI.say_status(text)` → dim status message

**Spinner wrapper**:
- `UI.spin("message") { slow_operation }` → dots spinner on stderr, returns block result, shows done/failed
- Falls back to plain `"message..."` on stderr when gems unavailable

**Interactive prompts**:
- `UI.main_menu` → arrow-key navigable menu with type-ahead filter
- `UI.repo_menu` / `UI.author_menu` → sub-menus for management
- `UI.ask(question)` → text input
- `UI.gems_available?` → check before entering interactive mode

## Files Modified

### `bin/core`
```ruby
begin
  require 'bundler/setup'
rescue LoadError, Bundler::GemNotFound
  # Gems unavailable — UI will degrade to plain text
end
```

### `lib/core/cli.rb`

**Interactive menu** (new `interactive_mode` method):
- When `command == nil && $stdin.tty? && UI.gems_available?` → show interactive menu loop
- Non-TTY or gems unavailable → defaults to `list_prs`
- Menu choices: List PRs, Start Review, Finish Review, Generate Context, Goto, List Worktrees, List Contexts, Manage Repos, Manage Authors, Help, Quit
- Sub-menus for repo/author management with `UI.ask` prompts for PR number/repo
- `Ctrl-C` handled gracefully via `rescue Interrupt, TTY::Reader::InputInterrupt`

**Spinner integration** (5 locations):

| Location | Spinner message | Wraps |
|----------|----------------|-------|
| `list_prs` | "Fetching PRs from N repos" | `fetcher.fetch_prs_needing_attention` |
| `handle_context_generation` | "Fetching PR data for repo #N" | `generator.generate` |
| `handle_start_review` | "Creating worktree for PR #N" | `manager.create` |
| `handle_start_review` | "Generating context file" | `context_gen.generate` |
| `handle_finish_review` | "Cleaning up worktree for PR #N" | `manager.remove` |

**Color output** — all `puts "Error: ..."` → `UI.say_error(...)`, `puts "✓ ..."` → `UI.say_ok(...)`, status/hint messages → `UI.say_status(...)`.

### `lib/core/formatter.rb`

Added `require_relative 'ui'` and colored `format_prs` / `format_pr_line`:
- Repo headers → `UI.bold`
- CI icons → `UI.ci_icon` (colored per status)
- PR numbers → `UI.dim`
- Draft markers → `UI.warning` (yellow)
- Tracked author `*` → `UI.success` (green)
- Age → `UI.dim`
- Total / legend → `UI.dim`
- Colors applied AFTER `ljust` padding to preserve alignment
- `format_file_changes` and `format_comments` unchanged (they write markdown files)

## Unchanged Files

- `config.rb` — no UI-facing output
- `github_client.rb` — no UI-facing output
- `pr_fetcher.rb` — no UI-facing output
- `context_generator.rb` — no UI-facing output
- `worktree_manager.rb` — no UI-facing output
- `tmux_manager.rb` — no UI-facing output

## Gotchas / Lessons Learned

1. **Ruby version mismatch**: The CLI is symlinked at `/usr/local/bin/core`. When invoked from a directory with a different `.ruby-version`, rbenv uses that Ruby — not the project's. Gems installed under 3.4.3 aren't visible to 3.4.2. Fix: install gems globally per Ruby version, or lazy-load with fallback.

2. **Bundler/setup at load time**: Hard `require 'bundler/setup'` crashes if Gemfile can't be resolved. Wrapping in begin/rescue makes the CLI resilient.

3. **ANSI codes break ljust**: `"\e[32m✓\e[0m"` is 1 visible char but 9 bytes. Calling `ljust` on colored strings produces misaligned columns. Always pad first, color second.

4. **TTY::Reader::InputInterrupt**: This exception class doesn't exist unless tty-prompt is loaded. Guard with `Interrupt` first in the rescue chain, and only enter interactive mode when `gems_available?`.

## Verification

```bash
# Colored PR table with spinner during fetch
core list

# Interactive menu (no args, in terminal)
core

# Spinners for worktree + context generation
core start-review 123 --repo owner/repo

# Non-TTY fallback (piped input defaults to list_prs)
echo "" | core

# Ctrl-C during menu exits cleanly
core  # then press Ctrl-C

# Works without gems (plain text fallback)
RBENV_VERSION=system ruby bin/core --help
```
