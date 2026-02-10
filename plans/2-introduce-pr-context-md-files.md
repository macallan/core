# Implementation Plan: PR Context Markdown Files

## Overview

Add functionality to generate and manage markdown files that store context for specific PRs. These files help users remember what a PR is about, what they've learned, and their review notes.

**Problem**: When reviewing PRs, it's easy to forget what the PR was about and what you had already learned.

**Goal**: Save context on specific PRs so you can quickly get up to speed when returning to them.

## Key Behavior

- Generate markdown files with PR metadata and review space
- Store files in a centralized location organized by repository
- Allow viewing/editing context files
- Fetch rich PR data from GitHub (description, files changed, comments)

## Requirements

1. Command to generate context file for a specific PR
2. Fetch comprehensive PR data from GitHub API
3. Create structured markdown file with:
   - PR metadata (title, author, status, description)
   - Files changed (list of modified files)
   - Review comments summary
   - Personal notes section (user can edit)
4. Store files in `~/.core/contexts/{owner}/{repo}/PR-{number}.md`
5. Command to list all saved contexts
6. Open context files in editor or display in terminal

## File Structure

### Storage Location
```
~/.core/contexts/
├── anthropics/
│   └── claude-code/
│       ├── PR-123.md
│       └── PR-456.md
└── rails/
    └── rails/
        └── PR-789.md
```

### Markdown File Template
```markdown
# PR #{number}: {title}

**Repository**: {owner}/{repo}
**Author**: @{author}
**Status**: {state} (Draft: {draft})
**Created**: {created_at}
**Updated**: {updated_at}
**URL**: {html_url}

## Description

{body}

## Files Changed ({files_count} files)

- path/to/file1.rb (+10, -5)
- path/to/file2.js (+20, -3)
...

## CI Status

{ci_status_summary}

## Review Comments ({review_comments_count} comments)

{recent_comments_summary}

---

## My Review Notes

<!-- Add your notes below -->

### First Review - {date}


### Follow-up - {date}


```

## Implementation by File

### 1. New File: `/Users/macallanbrown/cli/core/lib/core/context_generator.rb`

Create a new class to handle context file generation.

```ruby
require 'fileutils'
require_relative 'config'

module Core
  class ContextGenerator
    CONTEXT_DIR = File.expand_path('~/.core/contexts')

    def initialize(client)
      @client = client
    end

    def generate(repo, pr_number)
      # Fetch full PR data
      pr_data = fetch_pr_data(repo, pr_number)

      # Generate markdown content
      markdown = build_markdown(pr_data)

      # Save to file
      file_path = context_file_path(repo, pr_number)
      save_context(file_path, markdown)

      file_path
    end

    def list_contexts(repo = nil)
      # List all context files, optionally filtered by repo
    end

    def context_exists?(repo, pr_number)
      File.exist?(context_file_path(repo, pr_number))
    end

    private

    def fetch_pr_data(repo, pr_number)
      # Fetch PR data
      pr = @client.pr(repo, pr_number)

      # Fetch files changed
      files = @client.pr_files(repo, pr_number)

      # Fetch review comments (optional, may be expensive)
      comments = @client.pr_comments(repo, pr_number)

      # Fetch CI status
      ci_status = @client.combined_status(repo, pr['head']['sha'])

      {
        pr: pr,
        files: files,
        comments: comments,
        ci_status: ci_status
      }
    end

    def build_markdown(data)
      # Build markdown string from template
    end

    def context_file_path(repo, pr_number)
      owner, name = repo.split('/')
      File.join(CONTEXT_DIR, owner, name, "PR-#{pr_number}.md")
    end

    def save_context(file_path, content)
      FileUtils.mkdir_p(File.dirname(file_path))

      # If file exists, preserve user notes section
      if File.exist?(file_path)
        existing_content = File.read(file_path)
        content = merge_with_existing_notes(content, existing_content)
      end

      File.write(file_path, content)
    end

    def merge_with_existing_notes(new_content, old_content)
      # Extract "My Review Notes" section from old content
      # Append it to new content to preserve user's notes
    end
  end
end
```

### 2. Update: `/Users/macallanbrown/cli/core/lib/core/github_client.rb`

Add methods to fetch additional PR data needed for context files.

**Add these methods:**

```ruby
def pr(repo, number)
  # GET /repos/{owner}/{repo}/pulls/{number}
  api("repos/#{repo}/pulls/#{number}")
end

def pr_files(repo, number)
  # GET /repos/{owner}/{repo}/pulls/{number}/files
  api("repos/#{repo}/pulls/#{number}/files")
end

def pr_comments(repo, number, limit: 10)
  # GET /repos/{owner}/{repo}/pulls/{number}/comments
  # Return recent comments (limit to avoid huge output)
  comments = api("repos/#{repo}/pulls/#{number}/comments")
  comments.is_a?(Array) ? comments.last(limit) : []
end

def pr_reviews(repo, number)
  # GET /repos/{owner}/{repo}/pulls/{number}/reviews
  api("repos/#{repo}/pulls/#{number}/reviews")
end
```

### 3. Update: `/Users/macallanbrown/cli/core/lib/core/cli.rb`

Add new CLI commands for context management.

**Add after the author management commands (around line 145):**

```ruby
opts.on("--context PR_NUMBER", "Generate/update context file for a PR") do |pr_number|
  repo = determine_repo_from_args_or_prompt

  if repo.nil?
    puts "Error: Please specify repository with --repo or run from a git repository"
    exit 1
  end

  require_relative 'context_generator'
  generator = ContextGenerator.new(GitHubClient.new)

  file_path = generator.generate(repo, pr_number.to_i)
  puts "Context file generated: #{file_path}"

  # Optionally open in editor
  if ENV['EDITOR']
    system(ENV['EDITOR'], file_path)
  else
    puts "\nSet $EDITOR environment variable to auto-open in your editor"
  end

  exit 0
end

opts.on("--list-contexts [REPO]", "List all saved PR contexts") do |repo|
  require_relative 'context_generator'
  generator = ContextGenerator.new(GitHubClient.new)

  contexts = generator.list_contexts(repo)

  if contexts.empty?
    puts "No saved contexts found."
  else
    puts "Saved PR contexts:"
    contexts.each do |context|
      puts "  #{context}"
    end
  end

  exit 0
end

opts.on("--repo REPO", "Specify repository for context operations") do |repo|
  @options[:repo] = repo
end
```

**Add helper method in CLI class:**

```ruby
def determine_repo_from_args_or_prompt
  # Check if --repo flag was provided
  return @options[:repo] if @options[:repo]

  # Try to detect from git remote in current directory
  detect_repo_from_git
end

def detect_repo_from_git
  # Run: git config --get remote.origin.url
  output = `git config --get remote.origin.url 2>/dev/null`.strip
  return nil if output.empty?

  # Parse GitHub repo from URL
  # git@github.com:owner/repo.git or https://github.com/owner/repo.git
  if output =~ /github\.com[:|\/]([^\/]+\/[^\/\.]+)/
    $1
  end
end
```

### 4. Update: `/Users/macallanbrown/cli/core/lib/core/formatter.rb`

Add method to format file changes for context markdown.

```ruby
def self.format_file_changes(files)
  return "No files changed" if files.empty?

  files.map do |file|
    additions = file['additions'] || 0
    deletions = file['deletions'] || 0
    status = file['status'] || 'modified'

    "- #{file['filename']} [#{status}] (+#{additions}, -#{deletions})"
  end.join("\n")
end

def self.format_comments(comments)
  return "No comments yet" if comments.empty?

  comments.map do |comment|
    author = comment['user']['login']
    body = comment['body'][0..100] # Truncate long comments
    created = Time.parse(comment['created_at']).strftime('%Y-%m-%d')

    "**@#{author}** (#{created}): #{body}..."
  end.join("\n\n")
end
```

## CLI Commands

### Generate Context
```bash
# From within a git repository
core --context 123

# Specify repository explicitly
core --context 123 --repo anthropics/claude-code

# Short form (if we add command parsing)
core context 123
```

### List Contexts
```bash
# List all contexts
core --list-contexts

# List contexts for specific repo
core --list-contexts anthropics/claude-code
```

### View Context
```bash
# Open in $EDITOR
core --context 123  # If file exists, opens for editing

# Or just view with cat/bat
cat ~/.core/contexts/anthropics/claude-code/PR-123.md
```

## Expected Output

### Generated Context File Example
```markdown
# PR #24098: Add user authentication feature

**Repository**: anthropics/claude-code
**Author**: @alice
**Status**: open (Draft: false)
**Created**: 2026-01-20T10:30:00Z
**Updated**: 2026-01-25T15:45:00Z
**URL**: https://github.com/anthropics/claude-code/pull/24098

## Description

This PR implements JWT-based authentication for the API.

Key changes:
- Add authentication middleware
- Implement JWT token generation
- Add user session management

## Files Changed (8 files)

- lib/core/auth.rb [added] (+120, -0)
- lib/core/middleware/auth_middleware.rb [added] (+45, -0)
- lib/core/user.rb [modified] (+30, -5)
- lib/core/config.rb [modified] (+10, -2)
- test/auth_test.rb [added] (+80, -0)
- README.md [modified] (+15, -0)

## CI Status

✓ All checks passed (5/5)
- Build: success
- Tests: success
- Lint: success

## Review Comments (3 comments)

**@alice** (2026-01-24): Should we add rate limiting to the auth endpoint?

**@bob** (2026-01-25): The JWT expiration time seems too long...

---

## My Review Notes

<!-- Add your notes below -->

### First Review - 2026-01-25


### Follow-up


```

## Implementation Order

1. **GitHub API methods** - Add PR detail fetching to `github_client.rb`
2. **Context generator** - Create `context_generator.rb` with markdown generation
3. **CLI commands** - Add `--context` and `--list-contexts` options
4. **Formatter helpers** - Add file/comment formatting methods
5. **Testing** - Verify with real PRs
6. **Documentation** - Update README

## Critical Files

- `/Users/macallanbrown/cli/core/lib/core/context_generator.rb` (NEW) - Context generation logic
- `/Users/macallanbrown/cli/core/lib/core/github_client.rb` - Add PR detail API methods
- `/Users/macallanbrown/cli/core/lib/core/cli.rb` - Add context commands
- `/Users/macallanbrown/cli/core/lib/core/formatter.rb` - Add formatting helpers

## Verification / Testing

### 1. Basic Context Generation
```bash
# Generate context for a PR
./bin/core --context 123 --repo anthropics/claude-code

# Expected: Creates ~/.core/contexts/anthropics/claude-code/PR-123.md
# Expected: File contains PR metadata, description, files changed

# Verify file exists
ls -la ~/.core/contexts/anthropics/claude-code/
cat ~/.core/contexts/anthropics/claude-code/PR-123.md
```

### 2. Update Existing Context
```bash
# Add some notes to the file manually
echo -e "\n### My thoughts\n\nThis looks good" >> ~/.core/contexts/anthropics/claude-code/PR-123.md

# Regenerate context (PR may have been updated)
./bin/core --context 123 --repo anthropics/claude-code

# Expected: Metadata is updated but "My Review Notes" section is preserved
```

### 3. List Contexts
```bash
# Generate multiple contexts
./bin/core --context 123 --repo anthropics/claude-code
./bin/core --context 456 --repo anthropics/claude-code

# List all
./bin/core --list-contexts

# Expected: Shows all context files
```

### 4. Git Repository Detection
```bash
# Clone a tracked repo and cd into it
cd /tmp
git clone https://github.com/anthropics/claude-code.git
cd claude-code

# Generate context without --repo flag
../path/to/core/bin/core --context 123

# Expected: Auto-detects repo from git remote
```

### 5. Edge Cases
- PR that doesn't exist → Show error message
- Repo not tracked → Still allow context generation
- PR with no description → Handle empty body gracefully
- PR with many files (100+) → Limit or paginate file list
- Closed/merged PR → Still generate context, show status

## Design Decisions

### Why Markdown?
- Human-readable and editable
- Can be versioned in git if user wants
- Works with any text editor
- Can be rendered by tools like bat, glow, or in GitHub

### Why Centralized Storage (~/.core/contexts/)?
- User may not be in repo directory when reviewing
- Contexts persist even if repo is deleted locally
- Easy to back up entire contexts directory
- Organized by owner/repo for clarity

### Why Preserve User Notes on Regeneration?
- PR metadata may change (new commits, CI status updates)
- But user's review notes should persist
- Allows updating context without losing work

### File Limit Considerations
- For PRs with many files (50+), consider:
  - Only showing first 50 with "...and X more files"
  - Or grouping by directory
  - Or just showing file count and stats

### Comment Limit
- Fetch only recent comments (last 10) to avoid huge files
- User can always view full discussion on GitHub

## Future Enhancements (Out of Scope)

- Auto-generate context when listing PRs
- Show context status in PR list (✓ if context exists)
- `core context --diff 123` to show inline diffs in markdown
- Search contexts: `core context --search "authentication"`
- Export contexts to PDF or HTML
- Sync contexts to cloud storage
- Template customization in config
