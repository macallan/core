# Implementation Plan: List PRs Needing Attention

## Overview
Build a Ruby CLI tool that lists GitHub PRs needing attention by querying the GitHub API for PRs where the user is assigned, review-requested, or there's recent activity.

## Key Decisions
- **Authentication**: Use `gh` CLI (check if installed via `which gh`)
- **Config file**: `~/.core.yml` (YAML format)
- **Activity tracking**: Store last check timestamp per repo, flag PRs with updates since then
- **CLI framework**: Plain Ruby with OptionParser (minimal dependencies)
- **GitHub API**: Use `gh` CLI directly (no gem dependencies - zero external dependencies!)

## File Structure
```
core/
├── bin/
│   └── core                    # Executable entry point
├── lib/
│   └── core/
│       ├── cli.rb              # CLI argument parsing
│       ├── config.rb           # Config file handling
│       ├── github_client.rb   # gh CLI wrapper
│       ├── pr_fetcher.rb      # PR filtering/fetching logic
│       └── formatter.rb       # Output formatting
└── README.md
```

## Implementation Steps

### 1. Project Setup
**Files to create**: `bin/core`, `lib/core/` directory structure

- **No gem dependencies needed!** Pure Ruby with standard library only
- Make `bin/core` executable with proper shebang (`#!/usr/bin/env ruby`)
- Create lib/ directory structure
- Only requirement: `gh` CLI must be installed and authenticated

### 2. Config Management (`lib/core/config.rb`)
**Responsibilities**:
- Read/write `~/.core.yml`
- Validate config structure
- Provide defaults

**Config format**:
```yaml
repos:
  - owner/repo1
  - owner/repo2
last_checked:
  owner/repo1: 2026-01-25T10:30:00Z
  owner/repo2: 2026-01-25T09:15:00Z
```

**Methods**:
- `Config.load` - Load config from ~/.core.yml
- `Config.save(data)` - Write config
- `Config.update_last_checked(repo, timestamp)` - Update timestamp

### 3. GitHub Client (`lib/core/github_client.rb`)
**Responsibilities**:
- Check if `gh` CLI is installed
- Verify authentication status
- Execute `gh` commands and parse JSON output
- Handle errors

**Implementation**:
```ruby
class GitHubClient
  def initialize
    check_gh_installed!
    check_gh_authenticated!
  end

  def current_user
    @user ||= JSON.parse(`gh api user`)['login']
  end

  def list_prs(repo)
    # Use gh pr list with search filter - let GitHub do the filtering!
    cmd = "gh pr list --repo #{repo} --state open --search 'assignee:@me OR review-requested:@me' --json number,title,author,updatedAt,createdAt"
    output = `#{cmd}`
    raise "Failed to fetch PRs" unless $?.success?
    JSON.parse(output)
  end

  private

  def check_gh_installed!
    raise "GitHub CLI not installed" unless system('which gh > /dev/null 2>&1')
  end

  def check_gh_authenticated!
    raise "Not authenticated with gh CLI" unless system('gh auth status > /dev/null 2>&1')
  end
end
```

### 4. PR Fetching (`lib/core/pr_fetcher.rb`)
**Responsibilities**:
- Fetch open PRs from specified repos using `gh pr list` with search filters
- Let GitHub CLI do the filtering for assigned/review-requested
- Only filter for recent activity in Ruby code
- Return structured PR data

**Using gh CLI with search filter**:
```bash
# GitHub CLI filters PRs where user is assigned OR review-requested
gh pr list --repo owner/repo --state open \
  --search "assignee:@me OR review-requested:@me" \
  --json number,title,author,updatedAt,createdAt
```

**Filter logic (only for recent activity)**:
```ruby
def fetch_prs(repo, last_checked)
  # Let gh CLI filter by assigned/review-requested
  cmd = "gh pr list --repo #{repo} --state open --search 'assignee:@me OR review-requested:@me' --json number,title,author,updatedAt,createdAt"
  output = `#{cmd}`
  raise "Failed to fetch PRs" unless $?.success?
  prs = JSON.parse(output)

  # Only filter for recent activity if last_checked exists
  if last_checked
    last_checked_time = Time.parse(last_checked)
    prs.select { |pr| Time.parse(pr['updatedAt']) > last_checked_time }
  else
    prs  # First run - show all PRs
  end
end
```

### 5. Output Formatting (`lib/core/formatter.rb`)
**Responsibilities**:
- Format PR list for terminal display
- Show: PR number, title, author, age, status indicators

**Output format**:
```
PRs needing attention:

owner/repo1
  #123  [✓ CI] Fix authentication bug            @alice    2 days ago
  #124  [✗ CI] Add new feature                   @bob      5 hours ago

owner/repo2
  #456  [⋯ CI] Refactor database layer           @charlie  1 week ago

Total: 3 PRs
```

**Status indicators**:
- CI status: Check `pr.statuses` or latest workflow run
- Review status: Check approved/changes-requested reviews
- Merge conflicts: Check `mergeable_state`

### 6. CLI Interface (`lib/core/cli.rb`, `bin/core`)
**Commands**:
- `core list` - Show PRs needing attention
- `core list --refresh` - Ignore last_checked timestamp
- `core --help` - Show usage

**Flow**:
1. Parse arguments with OptionParser
2. Load config
3. Authenticate with GitHub
4. Fetch and filter PRs
5. Format and display output
6. Update last_checked timestamps

### 7. Error Handling
**Handle gracefully**:
- `gh` CLI not installed → "Please install GitHub CLI"
- Not authenticated → "Run `gh auth login` first"
- Config missing → Create default config, prompt for repos
- API rate limits → Show helpful error with reset time
- Network errors → Retry with exponential backoff

## Critical Files
- `bin/core` - Entry point (executable Ruby script)
- `lib/core/cli.rb` - Main CLI logic
- `lib/core/github_client.rb` - `gh` CLI wrapper
- `lib/core/pr_fetcher.rb` - Core PR filtering logic
- `lib/core/config.rb` - Config management
- `lib/core/formatter.rb` - Output formatting

## Verification

### Manual Testing
1. **Setup**:
   - Ensure `gh` CLI is installed and authenticated (`gh auth status`)
   - Create `~/.core.yml` with test repos
   - Make `bin/core` executable: `chmod +x bin/core`

2. **Test command**:
   ```bash
   ./bin/core list
   ```

3. **Expected output**:
   - List of PRs grouped by repo
   - Each PR shows number, title, author, age, CI status
   - Timestamps updated in ~/.core.yml

4. **Edge cases**:
   - Run with no repos in config → Helpful error
   - Run without `gh` auth → Clear error message
   - Run with no PRs → "No PRs need attention"
   - Run `--refresh` flag → Ignores last_checked

### Validation Checklist
- [ ] Can fetch PRs from configured repos
- [ ] Filters PRs where user is reviewer/assignee
- [ ] Shows PRs with activity since last check
- [ ] Updates last_checked timestamp after run
- [ ] Displays CI status, author, and age
- [ ] Handles GitHub API errors gracefully
- [ ] Works without `~/.core.yml` (creates default)

## Future Enhancements (out of scope)
- Auto-select next PR feature
- Interactive PR selection with arrow keys
- Open PR in browser
- Support for GitLab
- PR priority scoring
