# Implementation Plan: Start Reviewing with Git Worktrees

## Overview

Add functionality to quickly start reviewing PRs by creating isolated git worktrees. This allows developers to switch between writing code and reviewing PRs without losing their current work state.

**Problem**: Setting up to review a PR is difficult when you're in the middle of working on something. You need to stash changes, checkout the PR branch, deal with merge conflicts, and lose your current context.

**Goal**: Be able to instantly switch between reviewing PRs and writing code with isolated environments, while quickly getting caught up on previous conversations via context files.

## Key Decisions

- **Git Worktrees**: Use `git worktree` to create isolated checkouts for PR reviews
- **Integration**: Automatically create PR context file when starting review
- **State Management**: Track active worktrees in `~/.core.yml` config
- **Directory Structure**: Create worktrees adjacent to main repo (e.g., `{repo}-pr-{number}/`)
- **Custom Scripts**: Support repos with special setup needs (transcrypt, secrets, etc.)
- **Cleanup**: Provide commands to remove worktrees when review is complete
- **Navigation**: Generate shell command for users to cd into worktree (shell integration)

## Benefits of Git Worktrees

**Why worktrees solve the problem:**
1. **Isolation**: Each PR review gets its own directory - no conflicts with current work
2. **Fast switching**: No need to stash/unstash changes
3. **Parallel reviews**: Can have multiple PRs checked out simultaneously
4. **Preserve state**: Your main working directory remains untouched
5. **No branch pollution**: Worktrees can be ephemeral without cluttering branch list

**Git Worktree Basics:**
```bash
# Create worktree adjacent to main repo
cd ~/projects/myrepo
git worktree add -b pr-123-review ../myrepo-pr-123 origin/feature-branch

# Result:
# ~/projects/myrepo/           # Main repo
# ~/projects/myrepo-pr-123/    # New worktree

# List worktrees
git worktree list

# Remove worktree
git worktree remove ../myrepo-pr-123
```

## File Structure

### Worktree Storage

**Default (adjacent to repo):**
```
~/projects/
├── claude-code/              # Main repo
├── claude-code-pr-123/       # Worktree (sibling directory)
│   ├── .git                  # Points to ../claude-code/.git/worktrees/pr-123-review/
│   ├── lib/
│   └── ...
└── claude-code-pr-456/       # Another worktree
    └── ...
```

**Custom script (e.g., iheartjane with transcrypt):**
```
~/git/
└── iheartjane/               # Main repo
    └── worktrees/            # Custom script creates worktrees inside repo
        ├── vlad-feature/     # Script handles special setup (transcrypt, secrets)
        └── pr-123/
```

### Config State Tracking
```yaml
# ~/.core.yml
repos:
  - anthropics/claude-code
  - janetechinc/iheartjane
authors: []
last_checked:
  anthropics/claude-code: 2026-01-25T10:30:00Z

# Optional: Custom worktree creation scripts for repos with special setup needs
worktree_scripts:
  janetechinc/iheartjane: ~/bin/worktree.sh

worktrees:
  anthropics/claude-code:
    - pr_number: 123
      branch: feature-auth
      path: /Users/user/projects/claude-code-pr-123
      created_at: 2026-01-25T10:00:00Z
      context_file: /Users/user/.core/contexts/anthropics/claude-code/PR-123.md
  janetechinc/iheartjane:
    - pr_number: 456
      branch: vlad/new-feature
      path: /Users/user/git/iheartjane/worktrees/vlad-new-feature
      created_at: 2026-01-25T11:00:00Z
      context_file: /Users/user/.core/contexts/janetechinc/iheartjane/PR-456.md
```

## CLI Commands

### Start Reviewing a PR
```bash
# From within a git repository
core start-review 123

# Specify repository explicitly
core start-review 123 --repo anthropics/claude-code

# What it does:
# 1. Fetches PR info from GitHub
# 2. Creates git worktree adjacent to repo (or uses custom script)
# 3. Generates PR context file (auto-opens in $EDITOR)
# 4. Updates config with worktree state
# 5. Outputs: cd command to enter worktree
```

### List Active Worktrees
```bash
core list-worktrees

# Example output:
# Active PR worktrees:
#
# anthropics/claude-code
#   PR #123: /Users/user/projects/claude-code-pr-123
#   PR #456: /Users/user/projects/claude-code-pr-456
#
# janetechinc/iheartjane
#   PR #789: /Users/user/git/iheartjane/worktrees/vlad-new-feature
#
# Total: 3 active reviews
```

### Finish Review / Cleanup
```bash
# Remove worktree after review is complete
core finish-review 123

# Or specify repo
core finish-review 123 --repo anthropics/claude-code

# What it does:
# 1. Runs `git worktree remove`
# 2. Removes entry from config
# 3. Keeps context file (for reference)
```

### Navigate to Worktree
```bash
# Show cd command for worktree
core goto 123

# Outputs: cd /Users/user/projects/claude-code-pr-123
# User can: $(core goto 123) to actually navigate
```

## Implementation by File

### 1. New File: `/Users/macallanbrown/cli/core/lib/core/worktree_manager.rb`

Create a new class to handle git worktree operations.

```ruby
require 'fileutils'
require 'open3'
require_relative 'config'
require_relative 'github_client'

module Core
  class WorktreeManager
    class WorktreeError < StandardError; end

    def initialize(client)
      @client = client
      @config = Config.load
    end

    def create(repo, pr_number)
      # 1. Detect main repo path from current directory
      main_repo_path = detect_main_repo_path
      repo_name = File.basename(main_repo_path)

      # 2. Fetch PR data from GitHub
      pr_data = @client.pr(repo, pr_number)
      branch_name = pr_data['head']['ref']
      head_sha = pr_data['head']['sha']

      # 3. Check if repo has custom worktree script
      custom_script = @config.dig('worktree_scripts', repo)

      # 4. Create worktree using custom script or standard method
      if custom_script && File.exist?(File.expand_path(custom_script))
        worktree_path = create_worktree_with_script(custom_script, branch_name, pr_number)
      else
        # Standard: Create worktree adjacent to main repo
        worktree_path = determine_worktree_path(main_repo_path, pr_number)

        # Check if worktree already exists
        if worktree_exists?(worktree_path)
          return {
            exists: true,
            path: worktree_path,
            pr_number: pr_number,
            branch: branch_name
          }
        end

        # Fetch latest from remote
        fetch_remote(main_repo_path, branch_name)

        # Create worktree with standard method
        create_worktree_standard(main_repo_path, worktree_path, branch_name, pr_number)
      end

      # 5. Record in config
      save_worktree_state(repo, pr_number, branch_name, worktree_path)

      {
        exists: false,
        path: worktree_path,
        pr_number: pr_number,
        branch: branch_name,
        pr_data: pr_data
      }
    end

    def remove(repo, pr_number)
      # Find worktree in config
      worktree_info = find_worktree(repo, pr_number)
      return false unless worktree_info

      worktree_path = worktree_info[:path]

      # Remove git worktree
      remove_worktree(worktree_path)

      # Remove from config
      remove_worktree_state(repo, pr_number)

      true
    end

    def list(repo = nil)
      worktrees = @config['worktrees'] || {}

      if repo
        # Filter by repo
        { repo => worktrees[repo] || [] }
      else
        worktrees
      end
    end

    def goto(repo, pr_number)
      worktree_info = find_worktree(repo, pr_number)
      return nil unless worktree_info

      worktree_info[:path]
    end

    private

    def detect_main_repo_path
      # Find the git root directory
      output, status = Open3.capture2('git', 'rev-parse', '--show-toplevel')
      raise WorktreeError, "Not in a git repository" unless status.success?

      output.strip
    end

    def determine_worktree_path(repo_path, pr_number)
      # Create worktree adjacent to main repo
      # E.g., ~/projects/claude-code => ~/projects/claude-code-pr-123
      repo_name = File.basename(repo_path)
      parent_dir = File.dirname(repo_path)
      File.join(parent_dir, "#{repo_name}-pr-#{pr_number}")
    end

    def fetch_remote(repo_path, branch_name)
      # Fetch the PR branch from remote
      Dir.chdir(repo_path) do
        stdout, stderr, status = Open3.capture3('git', 'fetch', 'origin', branch_name)
        raise WorktreeError, "Failed to fetch branch: #{stderr}" unless status.success?
      end
    end

    def create_worktree_standard(repo_path, worktree_path, branch_name, pr_number)
      # Create worktree with tracking branch using standard git worktree
      Dir.chdir(repo_path) do
        local_branch = "pr-#{pr_number}-review"
        cmd = ['git', 'worktree', 'add', '-b', local_branch, worktree_path, "origin/#{branch_name}"]
        stdout, stderr, status = Open3.capture3(*cmd)

        unless status.success?
          raise WorktreeError, "Failed to create worktree: #{stderr}"
        end
      end
    end

    def create_worktree_with_script(script_path, branch_name, pr_number)
      # Run custom script to create worktree
      # Script usage: ~/bin/worktree.sh <branch-name>
      script_path = File.expand_path(script_path)

      stdout, stderr, status = Open3.capture3(script_path, branch_name)

      unless status.success?
        raise WorktreeError, "Custom script failed: #{stderr}"
      end

      # Parse output to extract worktree path
      # Script outputs: "Location: /path/to/worktree"
      if stdout =~ /Location:\s*(.+)$/
        path = $1.strip

        # Verify path exists
        unless File.directory?(path)
          raise WorktreeError, "Script succeeded but worktree not found at: #{path}"
        end

        return path
      else
        raise WorktreeError, "Could not parse worktree location from script output"
      end
    end

    def remove_worktree(worktree_path)
      # Use git worktree remove
      stdout, stderr, status = Open3.capture3('git', 'worktree', 'remove', worktree_path)

      # If it fails, try with --force (handles uncommitted changes)
      unless status.success?
        stdout, stderr, status = Open3.capture3('git', 'worktree', 'remove', '--force', worktree_path)
        raise WorktreeError, "Failed to remove worktree: #{stderr}" unless status.success?
      end
    end

    def worktree_exists?(path)
      File.directory?(path) && File.exist?(File.join(path, '.git'))
    end

    def save_worktree_state(repo, pr_number, branch, path)
      @config['worktrees'] ||= {}
      @config['worktrees'][repo] ||= []

      # Avoid duplicates
      existing = @config['worktrees'][repo].find { |w| w['pr_number'] == pr_number }
      return if existing

      @config['worktrees'][repo] << {
        'pr_number' => pr_number,
        'branch' => branch,
        'path' => path,
        'created_at' => Time.now.iso8601
      }

      Config.save(@config)
    end

    def remove_worktree_state(repo, pr_number)
      return unless @config['worktrees'] && @config['worktrees'][repo]

      @config['worktrees'][repo].reject! { |w| w['pr_number'] == pr_number }
      @config['worktrees'].delete(repo) if @config['worktrees'][repo].empty?

      Config.save(@config)
    end

    def find_worktree(repo, pr_number)
      return nil unless @config['worktrees'] && @config['worktrees'][repo]

      worktree = @config['worktrees'][repo].find { |w| w['pr_number'] == pr_number }
      return nil unless worktree

      {
        pr_number: worktree['pr_number'],
        branch: worktree['branch'],
        path: worktree['path'],
        created_at: worktree['created_at']
      }
    end
  end
end
```

### 2. Update: `/Users/macallanbrown/cli/core/lib/core/cli.rb`

Add new CLI commands for worktree management.

**Add after existing commands (around line 150):**

```ruby
opts.on("--start-review PR_NUMBER", "Start reviewing a PR with git worktree") do |pr_number|
  repo = determine_repo_from_args_or_prompt

  if repo.nil?
    puts "Error: Please specify repository with --repo or run from a git repository"
    exit 1
  end

  require_relative 'worktree_manager'
  require_relative 'context_generator'

  client = GitHubClient.new
  manager = WorktreeManager.new(client)
  context_gen = ContextGenerator.new(client)

  @action = -> {
    puts "Starting review for PR ##{pr_number} in #{repo}..."

    begin
      # Create worktree
      result = manager.create(repo, pr_number.to_i)

      if result[:exists]
        puts "Worktree already exists at: #{result[:path]}"
      else
        puts "✓ Created worktree at: #{result[:path]}"

        # Generate context file
        context_file = context_gen.generate(repo, pr_number.to_i)
        puts "✓ Generated context file: #{context_file}"

        # Open context in editor if $EDITOR is set
        if ENV['EDITOR']
          puts "✓ Opening context in #{ENV['EDITOR']}..."
          system(ENV['EDITOR'], context_file)
        end
      end

      # Show navigation command
      puts "\nTo navigate to worktree, run:"
      puts "  cd #{result[:path]}"
      puts "\nOr use: $(core goto #{pr_number}#{repo != determine_repo_from_args_or_prompt ? " --repo #{repo}" : ""})"

    rescue WorktreeManager::WorktreeError => e
      puts "Error: #{e.message}"
      exit 1
    end
  }

  exit 0
end

opts.on("--finish-review PR_NUMBER", "Clean up worktree after finishing review") do |pr_number|
  repo = determine_repo_from_args_or_prompt

  if repo.nil?
    puts "Error: Please specify repository with --repo or run from a git repository"
    exit 1
  end

  require_relative 'worktree_manager'
  manager = WorktreeManager.new(GitHubClient.new)

  @action = -> {
    puts "Finishing review for PR ##{pr_number} in #{repo}..."

    success = manager.remove(repo, pr_number.to_i)

    if success
      puts "✓ Removed worktree"
      puts "✓ Cleaned up config"
      puts "\nContext file preserved at: ~/.core/contexts/#{repo}/PR-#{pr_number}.md"
    else
      puts "No active worktree found for PR ##{pr_number}"
    end
  }

  exit 0
end

opts.on("--list-worktrees [REPO]", "List active PR worktrees") do |repo|
  repo ||= determine_repo_from_args_or_prompt

  require_relative 'worktree_manager'
  manager = WorktreeManager.new(GitHubClient.new)

  @action = -> {
    worktrees = manager.list(repo)

    if worktrees.empty? || worktrees.values.all?(&:empty?)
      puts "No active worktrees found."
    else
      puts "Active PR worktrees:\n\n"

      worktrees.each do |repo_name, wt_list|
        next if wt_list.nil? || wt_list.empty?

        puts repo_name
        wt_list.each do |wt|
          pr_number = wt['pr_number']
          path = wt['path']
          # Optionally fetch PR title for better display
          puts "  PR ##{pr_number}: #{path}"
        end
        puts
      end

      total = worktrees.values.flatten.compact.size
      puts "Total: #{total} active review#{'s' if total != 1}"
    end
  }

  exit 0
end

opts.on("--goto PR_NUMBER", "Show cd command for PR worktree") do |pr_number|
  repo = determine_repo_from_args_or_prompt

  if repo.nil?
    puts "Error: Please specify repository with --repo or run from a git repository"
    exit 1
  end

  require_relative 'worktree_manager'
  manager = WorktreeManager.new(GitHubClient.new)

  @action = -> {
    path = manager.goto(repo, pr_number.to_i)

    if path
      puts "cd #{path}"
    else
      puts "Error: No active worktree found for PR ##{pr_number}"
      exit 1
    end
  }

  exit 0
end
```

### 3. Update: `/Users/macallanbrown/cli/core/lib/core/github_client.rb`

No changes needed - existing `pr()` method already fetches necessary PR data including branch info.

### 4. Update: `/Users/macallanbrown/cli/core/lib/core/config.rb`

No changes needed - the config system already handles arbitrary keys and nested structures. The `worktrees` key will be automatically saved/loaded.

## Expected Output

### Starting a Review (Standard)
```bash
$ cd ~/projects/claude-code
$ ./bin/core --start-review 123

Starting review for PR #123 in anthropics/claude-code...
✓ Created worktree at: /Users/user/projects/claude-code-pr-123
✓ Generated context file: /Users/user/.core/contexts/anthropics/claude-code/PR-123.md
✓ Opening context in vim...

To navigate to worktree, run:
  cd /Users/user/projects/claude-code-pr-123

Or use: $(core goto 123)
```

### Starting a Review (Custom Script - iheartjane)
```bash
$ cd ~/git/iheartjane
$ ./bin/core --start-review 456

Starting review for PR #456 in janetechinc/iheartjane...
✓ Created worktree at: /Users/user/git/iheartjane/worktrees/vlad-new-feature
✓ Generated context file: /Users/user/.core/contexts/janetechinc/iheartjane/PR-456.md
✓ Opening context in vim...

To navigate to worktree, run:
  cd /Users/user/git/iheartjane/worktrees/vlad-new-feature

Or use: $(core goto 456)
```

### Listing Worktrees
```bash
$ ./bin/core --list-worktrees

Active PR worktrees:

anthropics/claude-code
  PR #123: /Users/user/projects/claude-code-pr-123
  PR #456: /Users/user/projects/claude-code-pr-456

janetechinc/iheartjane
  PR #789: /Users/user/git/iheartjane/worktrees/vlad-new-feature

Total: 3 active reviews
```

### Finishing a Review
```bash
$ ./bin/core --finish-review 123

Finishing review for PR #123 in anthropics/claude-code...
✓ Removed worktree
✓ Cleaned up config

Context file preserved at: ~/.core/contexts/anthropics/claude-code/PR-123.md
```

### Navigation Helper
```bash
$ ./bin/core --goto 123
cd /Users/user/projects/claude-code-pr-123

# Actually navigate (using command substitution)
$ $(./bin/core --goto 123)
$ pwd
/Users/user/projects/claude-code-pr-123
```

## Configuring Custom Worktree Scripts

For repositories that require special setup (encrypted files, secret linking, custom hooks), you can configure a custom script to handle worktree creation.

### Example: iheartjane with transcrypt

**1. Create/verify your custom script** at `~/bin/worktree.sh`:
```bash
#!/bin/bash
# Script creates worktree with transcrypt and galaxy-secrets support
# Usage: ~/bin/worktree.sh <branch-name>
# Outputs: "Location: /path/to/worktree"
```

**2. Add to config** at `~/.core.yml`:
```yaml
worktree_scripts:
  janetechinc/iheartjane: ~/bin/worktree.sh
```

**3. Use normally:**
```bash
cd ~/git/iheartjane
core --start-review 456
# Automatically uses custom script
```

### Script Requirements

Custom scripts must:
1. **Accept branch name as first argument**: `script.sh <branch-name>`
2. **Output worktree location**: Must print `Location: /path/to/worktree` to stdout
3. **Exit with status 0** on success, non-zero on failure
4. **Create valid git worktree**: The path must be a working git worktree

### How It Works

When `core --start-review` runs:
1. Checks config for `worktree_scripts[repo]`
2. If custom script exists and is executable:
   - Runs: `script.sh <pr-branch-name>`
   - Parses stdout for `Location: <path>`
   - Uses that path for the worktree
3. Otherwise uses standard `git worktree add` adjacent to repo

**Note:** Cleanup always uses standard `git worktree remove`, regardless of how the worktree was created.

## Implementation Order

1. **WorktreeManager class** - Create `worktree_manager.rb` with core worktree operations
2. **Custom script support** - Add logic to detect and use custom scripts
3. **CLI commands** - Add `--start-review`, `--finish-review`, `--list-worktrees`, `--goto`
4. **Config integration** - Ensure worktree state and scripts persist in `~/.core.yml`
5. **Context auto-generation** - Integrate with existing `ContextGenerator`
5. **Error handling** - Handle edge cases (not in git repo, branch doesn't exist, etc.)
6. **Testing** - Verify with real PRs and multiple worktrees
7. **Documentation** - Update README with worktree workflow

## Critical Files

- `/Users/macallanbrown/cli/core/lib/core/worktree_manager.rb` (NEW) - Worktree management logic
- `/Users/macallanbrown/cli/core/lib/core/cli.rb` - Add worktree commands
- `/Users/macallanbrown/cli/core/lib/core/context_generator.rb` - Already exists, no changes needed
- `/Users/macallanbrown/cli/core/lib/core/config.rb` - Already supports nested data, no changes needed

## Verification / Testing

### 1. Create First Worktree (Standard Method)
```bash
# From main repo
cd ~/projects/claude-code

# Start review
./bin/core --start-review 123

# Verify worktree created adjacent to repo
ls -la ~/projects/claude-code-pr-123

# Verify git worktree registered
git worktree list
# Expected output includes: ~/projects/claude-code-pr-123

# Verify context file created
cat ~/.core/contexts/anthropics/claude-code/PR-123.md

# Verify config updated
cat ~/.core.yml | grep -A 5 worktrees
```

### 2. Create Worktree with Custom Script
```bash
# Set up custom script in config first
# Edit ~/.core.yml to add:
#   worktree_scripts:
#     janetechinc/iheartjane: ~/bin/worktree.sh

cd ~/git/iheartjane

# Start review
./bin/core --start-review 456

# Verify worktree created using custom script location
ls -la ~/git/iheartjane/worktrees/vlad-new-feature  # Custom script creates inside repo

# Verify transcrypt and secrets are set up (custom script responsibility)
ls -la ~/git/iheartjane/worktrees/vlad-new-feature/client/config/secrets.galaxy.json

# Verify git worktree registered
cd ~/git/iheartjane
git worktree list
```

### 3. Navigate and Work in Worktree
```bash
# Use goto command
$(./bin/core --goto 123)

# Verify we're in worktree
pwd  # Should be: ~/projects/claude-code-pr-123

# Check branch
git branch  # Should show: pr-123-review

# Make some changes, commit
echo "test" >> test.txt
git add test.txt
git commit -m "Test commit in worktree"

# Return to main repo
cd ~/projects/claude-code

# Verify main repo is clean
git status  # Should show original state
```

### 4. Multiple Worktrees
```bash
# Create second worktree
cd ~/projects/claude-code
./bin/core --start-review 456

# List all worktrees
./bin/core --list-worktrees

# Expected: Shows both PR 123 and PR 456

# Verify both are adjacent
ls ~/projects/ | grep claude-code
# Should show:
#   claude-code
#   claude-code-pr-123
#   claude-code-pr-456

# Verify git knows about both
git worktree list
```

### 5. Cleanup
```bash
# Finish review
cd ~/projects/claude-code
./bin/core --finish-review 123

# Verify worktree removed
ls ~/projects/claude-code-pr-123  # Should not exist (directory removed)

# Verify git worktree removed
git worktree list  # Should not show pr-123

# Verify context preserved
cat ~/.core/contexts/anthropics/claude-code/PR-123.md  # Should still exist

# Verify config updated
cat ~/.core.yml | grep -A 5 worktrees  # Should not show pr-123
```

### 5. Edge Cases

**Worktree already exists:**
```bash
./bin/core --start-review 123
./bin/core --start-review 123  # Run again

# Expected: "Worktree already exists" message, doesn't error
```

**Not in git repo:**
```bash
cd /tmp
./bin/core --start-review 123

# Expected: Error message "Not in a git repository"
```

**Branch doesn't exist:**
```bash
./bin/core --start-review 999999

# Expected: GitHub API error or fetch error
```

**Force cleanup (uncommitted changes):**
```bash
$(./bin/core --goto 123)
echo "test" >> file.txt  # Don't commit

cd ~/projects/claude-code
./bin/core --finish-review 123

# Expected: Uses --force flag to remove worktree
```

## Design Decisions

### Why Adjacent Worktrees (Not Centralized)?

**Decision:** Create worktrees next to (sibling of) the main repository.

```
~/projects/
├── claude-code/          # Main repo
├── claude-code-pr-123/   # Worktree (sibling)
└── claude-code-pr-456/   # Another worktree
```

**Advantages:**
- **Discoverable**: `ls ~/projects` shows all active reviews naturally
- **Shorter paths**: `cd ../claude-code-pr-123` is simpler than `cd ~/.core/worktrees/claude-code/pr-123`
- **Git semantics**: Worktrees are inherently tied to their parent repo's location, so co-location makes sense
- **Multiple clones**: Different repo clones can have their own worktrees without conflicts
- **Common practice**: Many developers already do this manually

**Alternative considered:** Centralized storage at `~/.core/worktrees/`
```
~/.core/worktrees/claude-code/pr-123/
```
**Rejected because:**
- Not discoverable when browsing projects
- Git worktrees don't benefit from centralization (they're location-dependent)
- Longer, less intuitive paths

**Exception:** Custom scripts (like iheartjane) can place worktrees wherever they want, including inside the repo in a `worktrees/` subdirectory. The tool respects the script's choice.

### Why Track in Config vs Git Worktree List?

Git already tracks worktrees in `.git/worktrees/`. Why duplicate in config?

**Reasons:**
1. **Richer metadata**: Store creation time, PR number, context file path
2. **Persistence**: Config survives even if worktree is manually deleted
3. **Cross-repo view**: Can list all reviews across multiple projects
4. **Future features**: Can add review status, notes, etc.

### Why Not Auto-CD?

Cannot directly change the user's shell directory from a Ruby script. Options:

**Option 1: Output cd command** (chosen)
```bash
$(core goto 123)  # Command substitution executes output
```

**Option 2: Shell function wrapper** (future enhancement)
```bash
# In ~/.bashrc or ~/.zshrc
core() {
  if [[ "$1" == "goto" ]]; then
    cd $(command core "$@")
  else
    command core "$@"
  fi
}
```

**Option 3: Generate .envrc file** (for direnv users)
Could create `.envrc` in worktree that sets environment variables.

### Branch Naming Convention

**Local branch name:** `pr-{number}-review`

**Why:**
- Clear indication it's for review
- Avoids conflicts with other local branches
- Easy to identify and clean up

**Alternative:** Use remote branch name directly
**Rejected because:** Risk of confusion with actual feature branch

### Cleanup Policy

**What gets removed:**
- Git worktree directory
- Git metadata in `.git/worktrees/`
- Config entry

**What gets preserved:**
- Context markdown file (user's notes are valuable)
- Main repository state (untouched)

**Rationale:** Context files contain user's review notes which should survive cleanup. Disk space is cheap, notes are valuable.

### Custom Script Support

**Why support custom creation scripts?**

Some repositories have special requirements that standard `git worktree add` can't handle:
- Encrypted files (transcrypt, git-crypt)
- Secret/config file linking
- Special build setup or dependencies
- Custom directory structures

**Example: iheartjane**
- Uses `transcrypt` for encrypted files in the repo
- Needs to link `~/.galaxy-secrets.json` to worktree
- Requires special symlink setup for transcrypt to work
- Standard `git worktree add` would create a worktree with encrypted (unreadable) files

**Design choices:**
1. **Config-based**: Users explicitly declare custom scripts in `~/.core.yml`
2. **Script interface**: Simple contract - accept branch name, output path
3. **Cleanup stays standard**: Custom setup is for creation only; `git worktree remove` handles cleanup universally
4. **Path flexibility**: Scripts can create worktrees wherever they need (inside repo, adjacent, elsewhere)
5. **Fallback**: If script not configured or fails, fall back to standard method

**Alternative considered:** Auto-detect special repo needs
**Rejected because:**
- Too many edge cases (how to detect transcrypt? git-crypt? other tools?)
- Better to let users explicitly configure their needs
- Explicit config is more maintainable and debuggable

## Integration with Existing Features

### With PR Context Files

**Flow:**
1. User runs `--start-review 123`
2. Worktree is created
3. Context file is auto-generated (uses existing `ContextGenerator`)
4. Context file opens in `$EDITOR` automatically
5. User reviews code and adds notes to context file
6. User finishes review with `--finish-review 123`
7. Context file persists for future reference

**Benefit:** Single command gets you from "I need to review this PR" to "I'm reviewing with full context open".

### With PR Listing

**Enhancement idea** (future):
Add indicator in `core list` output showing if worktree exists:

```bash
PRs needing attention:

anthropics/claude-code
  #123  [✓ CI] [📂 active] Fix authentication bug    @alice    2 days ago
  #124  [✗ CI]            Add new feature            @bob      5 hours ago
```

The `[📂 active]` indicator shows a worktree exists.

### With Author Tracking

No direct integration, but benefits from it:
- `core list` shows PRs from tracked authors
- User can `--start-review` any PR from the list
- Smooth workflow: list → pick → review

## Common Workflows

### Workflow 1: Quick Review
```bash
# See what needs attention
core list

# Start reviewing
core --start-review 123

# Opens context file automatically, shows cd command
$(core goto 123)

# Review code, test changes
npm test

# Finish review
cd ~/projects/claude-code
core --finish-review 123
```

### Workflow 2: Multiple Simultaneous Reviews
```bash
# Start two reviews
core --start-review 123
core --start-review 456

# Switch between them
$(core goto 123)
# ... review ...

$(core goto 456)
# ... review ...

# See what's active
core --list-worktrees

# Finish when done
core --finish-review 123
core --finish-review 456
```

### Workflow 3: Interrupted Review
```bash
# Start review
core --start-review 123
$(core goto 123)

# Get interrupted, switch to main work
cd ~/projects/claude-code

# Later, come back to review
$(core goto 123)
# Context is preserved, can continue where left off
```

### Workflow 4: Custom Script (iheartjane with transcrypt)
```bash
# One-time setup: Add script to config
# Edit ~/.core.yml:
#   worktree_scripts:
#     janetechinc/iheartjane: ~/bin/worktree.sh

# Start review (from iheartjane repo)
cd ~/git/iheartjane
core --start-review 456

# Script automatically:
# - Creates worktree with transcrypt support
# - Links galaxy-secrets.json
# - Sets up encrypted files

$(core goto 456)
# Worktree is ready with all secrets decrypted

# Work, then cleanup
cd ~/git/iheartjane
core --finish-review 456
# Standard cleanup works even for custom-created worktrees
```

## Error Handling

**Handle gracefully:**
- Not in git repository → Clear error: "Please run from within a git repository"
- PR doesn't exist → GitHub API error with PR number
- Branch already checked out → Suggest using existing worktree or cleaning up
- Worktree path already exists (but not tracked) → Offer to adopt or use different path
- Git worktree operation fails → Show git error, suggest manual cleanup
- No $EDITOR set → Skip auto-opening context file, show path instead
- Custom script not found → Show error: "Custom script not found at {path}", fall back to standard method
- Custom script fails (non-zero exit) → Show stderr output, explain script failed
- Custom script doesn't output location → Show error: "Could not parse worktree location from script output"
- Custom script output invalid path → Show error: "Script succeeded but worktree not found at {path}"

## Shell Integration (Future Enhancement)

For even smoother workflow, users can add to their `~/.bashrc` or `~/.zshrc`:

```bash
# Auto-cd when using goto command
function core-goto() {
  local path=$(core --goto "$@")
  if [ $? -eq 0 ]; then
    cd "$path"
  fi
}
alias cgoto='core-goto'

# Quick start review and navigate
function core-review() {
  core --start-review "$@"
  if [ $? -eq 0 ]; then
    eval "$(core --goto $1)"
  fi
}
alias creview='core-review'
```

Usage:
```bash
cgoto 123        # Navigate to PR 123 worktree
creview 123      # Start review and auto-navigate
```

## Future Enhancements (Out of Scope)

- Auto-cleanup stale worktrees (>30 days old)
- Integration with PR status: auto-remove worktree when PR is merged/closed
- Open PR in browser from worktree: `core open`
- Show git diff summary in worktree list
- Support for GitLab merge requests
- Worktree templates (auto-run setup scripts)
- Sync worktree branch with latest commits: `core sync 123`
- Show uncommitted changes indicator in list
- Terminal multiplexer integration (tmux/screen sessions per worktree)
- VSCode workspace generation per worktree
