module Core
  module Commands
    class FinishReview < Base
      def run
        pr_number = @args.shift&.to_i

        require_relative '../worktree_manager'
        manager = WorktreeManager.new(client)

        unless pr_number && pr_number > 0
          if $stdin.tty? && UI.gems_available?
            selections = pick_worktrees(manager)
            return if selections.nil? || selections.empty?

            finish_multiple_reviews(manager, selections)
            return
          else
            UI.say_error("Missing PR number argument")
            puts "Usage: core finish-review [PR_NUMBER] [--repo owner/repo]"
            exit 1
          end
        else
          repo = determine_repo_from_args_or_prompt

          if repo.nil?
            UI.say_error("Please specify repository with --repo or run from a git repository")
            exit 1
          end
        end

        finish_single_review(manager, repo, pr_number)
      end

      private

      def pick_worktrees(manager)
        worktrees = manager.list
        flat = worktrees.flat_map do |repo_name, wt_list|
          (wt_list || []).map { |wt| wt.merge('repo' => repo_name) }
        end

        if flat.empty?
          UI.say_status("No active worktrees")
          return nil
        end

        UI.select_worktree(flat, multi: true)
      end

      def finish_single_review(manager, repo, pr_number)
        UI.say_status("Finishing review for PR ##{pr_number} in #{repo}...")

        success = UI.spin("Cleaning up worktree for PR ##{pr_number}") do
          manager.remove(repo, pr_number)
        end

        if success
          UI.say_ok("Removed worktree")
          UI.say_ok("Deleted local review branch")
          UI.say_ok("Cleaned up config")
          UI.say_status("Context file preserved at: ~/.core/contexts/#{repo}/PR-#{pr_number}.md")
        else
          puts "No active worktree found for PR ##{pr_number}"
        end
      end

      def finish_multiple_reviews(manager, selections)
        total = selections.length
        UI.say_status("Finishing #{total} review#{total > 1 ? 's' : ''}...")
        puts

        succeeded = 0
        failed = 0

        selections.each_with_index do |selection, index|
          repo = selection['repo']
          pr_number = selection['pr_number']

          puts UI.dim("#{index + 1}/#{total}") + " PR ##{pr_number} in #{repo}"

          success = UI.spin("Cleaning up worktree") do
            manager.remove(repo, pr_number)
          end

          if success
            UI.say_ok("Cleaned up PR ##{pr_number}")
            succeeded += 1
          else
            UI.say_error("Failed to clean up PR ##{pr_number}")
            failed += 1
          end

          puts if index < selections.length - 1
        end

        puts
        UI.say_status("Finished: #{succeeded} succeeded#{", #{failed} failed" if failed > 0}")
      end
    end
  end
end
