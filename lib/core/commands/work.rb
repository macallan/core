require 'open3'

module Core
  module Commands
    class Work < Base
      def run
        branch_name = @args.shift

        unless branch_name
          if $stdin.tty? && UI.gems_available?
            branch_name = UI.ask('Branch name:')
          end

          unless branch_name && !branch_name.strip.empty?
            UI.say_error("Missing branch name argument")
            puts "Usage: core work BRANCH [--repo owner/repo] [--base BASE_BRANCH]"
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

        begin
          result = UI.spin("Setting up worktree for #{branch_name}") do
            manager.create_for_work(repo, branch_name, base_branch: base_branch)
          end

          if result[:exists]
            puts "Worktree already exists at: #{result[:path]}"
          else
            UI.say_ok("Created worktree at: #{result[:path]}")
          end

          # Copy .envrc.local from main repo to worktree if it exists
          main_repo = detect_repo_from_git_toplevel
          if main_repo
            envrc_local_src = File.join(main_repo, '.envrc.local')
            envrc_local_dst = File.join(result[:path], '.envrc.local')
            if File.exist?(envrc_local_src) && !File.exist?(envrc_local_dst)
              FileUtils.cp(envrc_local_src, envrc_local_dst)
            end
          end

          # Auto-allow direnv in the new worktree if .envrc exists
          envrc_path = File.join(result[:path], '.envrc')
          if File.exist?(envrc_path)
            Open3.capture3('direnv', 'allow', result[:path])
          end

          window_name = branch_name.gsub('/', '-')
          tmux_created = handle_tmux_window_creation(result[:path], window_name)
          puts "cd #{result[:path]}" unless tmux_created

        rescue WorktreeManager::WorktreeError => e
          UI.say_error(e.message)
          exit 1
        end
      end
    end
  end
end
