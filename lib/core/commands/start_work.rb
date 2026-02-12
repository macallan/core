module Core
  module Commands
    class StartWork < Base
      def run
        branch_name = @args.shift

        unless branch_name
          if $stdin.tty? && UI.gems_available?
            branch_name = UI.ask('Branch name:')
          end

          unless branch_name && !branch_name.strip.empty?
            UI.say_error("Missing branch name argument")
            puts "Usage: core start-work BRANCH_NAME [--repo owner/repo] [--base BASE_BRANCH]"
            exit 1
          end
        end

        repo = determine_repo_from_args_or_prompt

        if repo.nil?
          UI.say_error("Please specify repository with --repo or run from a git repository")
          exit 1
        end

        base_branch = @options[:base]

        require_relative '../worktree_manager'

        manager = WorktreeManager.new(client)

        UI.say_status("Starting worktree for #{branch_name} in #{repo}...")

        begin
          result = UI.spin("Creating worktree for #{branch_name}") do
            manager.create_for_work(repo, branch_name, base_branch: base_branch)
          end

          if result[:exists]
            puts "Worktree already exists at: #{result[:path]}"
          else
            UI.say_ok("Created worktree at: #{result[:path]}")
          end

          tmux_created = handle_tmux_window_creation(result[:path], branch_name)
          puts "cd #{result[:path]}" unless tmux_created

        rescue WorktreeManager::WorktreeError => e
          UI.say_error(e.message)
          exit 1
        end
      end
    end
  end
end
