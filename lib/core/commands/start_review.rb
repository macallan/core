module Core
  module Commands
    class StartReview < Base
      def run
        pr_number = @args.shift&.to_i
        pr_number = nil if pr_number && pr_number <= 0

        repo = determine_repo_from_args_or_prompt

        if pr_number.nil? && $stdin.tty? && UI.gems_available?
          selection = pick_pr(repo)
          return if selection.nil?

          repo = selection[:repo]
          pr_number = selection[:number]
        end

        unless pr_number
          UI.say_error("Missing PR number argument")
          puts "Usage: core start-review [PR_NUMBER] [--repo owner/repo]"
          exit 1
        end

        if repo.nil?
          UI.say_error("Please specify repository with --repo or run from a git repository")
          exit 1
        end

        require_relative '../worktree_manager'
        require_relative '../context_generator'

        manager = WorktreeManager.new(client)
        context_gen = ContextGenerator.new(client)

        UI.say_status("Starting review for PR ##{pr_number} in #{repo}...")

        begin
          result = UI.spin("Creating worktree for PR ##{pr_number}") do
            manager.create(repo, pr_number)
          end

          if result[:exists]
            puts "Worktree already exists at: #{result[:path]}"
          else
            UI.say_ok("Created worktree at: #{result[:path]}")

            context_file = UI.spin("Generating context file") do
              context_gen.generate(repo, pr_number)
            end
            UI.say_ok("Generated context file: #{context_file}")
          end

          pr_title = result[:pr_data]&.dig('title') || client.pr(repo, pr_number)&.dig('title')
          tmux_created = handle_tmux_window_creation(result[:path], pr_number, pr_title: pr_title)
          puts "cd #{result[:path]}" unless tmux_created

        rescue WorktreeManager::WorktreeError => e
          UI.say_error(e.message)
          exit 1
        end
      end

      private

      def pick_pr(repo)
        repos = repo ? [repo] : Config.repos

        if repos.empty?
          UI.say_error("No repositories configured. Add one with: core add-repo owner/repo")
          return nil
        end

        cached = PRCache.read

        if cached && !cached[:prs_by_repo].empty?
          # Show cached data immediately with background refresh
          queue = Thread::Queue.new

          bg_thread = PRCache.refresh_in_background(
            on_complete: ->(fresh) { queue.push(UI.build_pr_choices(fresh)) }
          ) do
            PRFetcher.new(client).fetch_prs_needing_attention(repos, refresh: true)
          end

          selection = UI.select_pr(cached[:prs_by_repo], update_queue: queue)
          bg_thread&.kill if bg_thread&.alive?
          selection
        else
          # No cache — fetch with spinner
          fetcher = PRFetcher.new(client)

          prs_by_repo = UI.spin("Fetching open PRs") do
            fetcher.fetch_prs_needing_attention(repos, refresh: true)
          end

          PRCache.write(prs_by_repo)

          if prs_by_repo.empty?
            UI.say_status("No PRs needing attention")
            return nil
          end

          UI.select_pr(prs_by_repo)
        end
      end
    end
  end
end
