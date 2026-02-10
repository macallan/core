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

      # 3. Check if worktree already exists in config
      existing_worktree = find_worktree(repo, pr_number)
      if existing_worktree && worktree_exists?(existing_worktree[:path])
        return {
          exists: true,
          path: existing_worktree[:path],
          pr_number: pr_number,
          branch: branch_name
        }
      end

      # 4. Prune any stale worktrees and check if branch is already in use
      prune_stale_worktrees(main_repo_path)
      existing_git_worktree = find_existing_git_worktree(main_repo_path, branch_name)
      if existing_git_worktree
        # Worktree exists in git but not in our config - add it to config
        save_worktree_state(repo, pr_number, branch_name, existing_git_worktree)
        return {
          exists: true,
          path: existing_git_worktree,
          pr_number: pr_number,
          branch: branch_name
        }
      end

      # 5. Check if repo has custom worktree script
      custom_script = @config.dig('worktree_scripts', repo)

      # 6. Create worktree using custom script or standard method
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

      # 7. Record in config
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
      branch_name = worktree_info[:branch]

      # Detect main repo path BEFORE removing worktree (in case we're currently in the worktree)
      main_repo_path = detect_main_repo_path rescue nil

      # If we can't find the main repo, we can't proceed with cleanup
      unless main_repo_path
        raise WorktreeError, "Could not locate main repository. Please cd to the main repo and try again."
      end

      # Change to main repo directory to run cleanup commands
      Dir.chdir(main_repo_path) do
        # Prune stale worktree references first
        prune_stale_worktrees(main_repo_path)

        # Try to remove git worktree, but continue even if it fails
        begin
          remove_worktree(worktree_path) if worktree_exists?(worktree_path)
        rescue WorktreeError => e
          # Log the error but continue with cleanup
          $stderr.puts "Warning: #{e.message}"
        end

        # Delete local review branches (both standard and custom script branches)
        delete_review_branch(pr_number, branch_name, main_repo_path)
      end

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
      $stderr.puts "  Fetching #{branch_name} from origin..."
      Dir.chdir(repo_path) do
        stdout, stderr, status = Open3.capture3('git', 'fetch', 'origin', branch_name)
        raise WorktreeError, "Failed to fetch branch: #{stderr}" unless status.success?
      end
    end

    def create_worktree_standard(repo_path, worktree_path, branch_name, pr_number)
      # Create worktree with tracking branch using standard git worktree
      $stderr.puts "  Creating worktree at #{File.basename(worktree_path)}..."
      Dir.chdir(repo_path) do
        local_branch = "pr-#{pr_number}-review"

        # Use -B to reset branch if it exists (more robust than -b)
        cmd = ['git', 'worktree', 'add', '-B', local_branch, worktree_path, "origin/#{branch_name}"]
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
      $stderr.puts "  Running custom worktree script..."

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

    def delete_review_branch(pr_number, remote_branch_name, main_repo_path = nil)
      # Delete both the standard review branch and the branch created by custom scripts
      branches_to_delete = [
        "pr-#{pr_number}-review",  # Standard method branch
        remote_branch_name          # Custom script might create this
      ].uniq

      # Need to run in the main repo directory
      main_repo_path ||= detect_main_repo_path rescue nil
      return unless main_repo_path

      Dir.chdir(main_repo_path) do
        branches_to_delete.each do |branch_name|
          # Check if branch exists
          stdout, stderr, status = Open3.capture3('git', 'rev-parse', '--verify', branch_name)
          next unless status.success?

          # Delete the branch (use -D to force delete even if not fully merged)
          Open3.capture3('git', 'branch', '-D', branch_name)
          # Silently ignore errors - branch might have already been deleted
        end
      end
    end

    def worktree_exists?(path)
      File.directory?(path) && File.exist?(File.join(path, '.git'))
    end

    def prune_stale_worktrees(repo_path)
      # Remove worktree references where the directory no longer exists
      Dir.chdir(repo_path) do
        Open3.capture3('git', 'worktree', 'prune')
        # Silently ignore errors - this is a cleanup operation
      end
    end

    def find_existing_git_worktree(repo_path, branch_name)
      # Check if git already has a worktree for this branch
      # This handles cases where worktrees exist but aren't in our config
      Dir.chdir(repo_path) do
        stdout, stderr, status = Open3.capture3('git', 'worktree', 'list', '--porcelain')
        return nil unless status.success?

        # Parse worktree list output
        # Format: worktree <path>\nHEAD <sha>\nbranch <branch>\n\n
        worktrees = stdout.split("\n\n")
        worktrees.each do |worktree_block|
          lines = worktree_block.split("\n")
          path_line = lines.find { |l| l.start_with?('worktree ') }
          branch_line = lines.find { |l| l.start_with?('branch ') }

          next unless path_line && branch_line

          path = path_line.sub('worktree ', '')
          branch = branch_line.sub('branch ', '').sub('refs/heads/', '')

          # Check if this worktree is using our target branch
          if branch == branch_name || branch == "pr-#{branch_name}-review"
            return path if File.directory?(path)
          end
        end
      end

      nil
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
