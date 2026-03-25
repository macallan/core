module Core
  module Commands
    class Clean < Base
      def run
        require_relative '../worktree_manager'
        manager = WorktreeManager.new(client)

        unless $stdin.tty? && UI.gems_available?
          UI.say_error("Clean requires an interactive terminal")
          exit 1
        end

        selections = pick_worktrees(manager)
        return if selections.nil? || selections.empty?

        remove_worktrees(manager, selections)
      end

      private

      def pick_worktrees(manager)
        all = manager.list_all
        flat = []

        # Review worktrees
        (all[:review] || {}).each do |repo_name, wt_list|
          (wt_list || []).each { |wt| flat << wt.merge('repo' => repo_name, 'type' => 'review') }
        end

        # Work worktrees
        (all[:work] || {}).each do |repo_name, wt_list|
          (wt_list || []).each { |wt| flat << wt.merge('repo' => repo_name, 'type' => 'work') }
        end

        if flat.empty?
          UI.say_status("No active worktrees")
          return nil
        end

        UI.select_worktree(flat, multi: true)
      end

      def remove_worktrees(manager, selections)
        total = selections.length
        UI.say_status("Removing #{total} worktree#{total > 1 ? 's' : ''}...")
        puts

        succeeded = 0
        failed = 0

        selections.each_with_index do |selection, index|
          repo = selection['repo']
          type = selection['type']
          label = type == 'review' ? "PR ##{selection['pr_number']}" : selection['branch']

          puts UI.dim("#{index + 1}/#{total}") + " #{label} in #{repo}"

          success = UI.spin("Removing worktree") do
            if type == 'review'
              manager.remove(repo, selection['pr_number'])
            else
              manager.remove_work(repo, selection['branch'])
            end
          end

          if success
            UI.say_ok("Removed #{label}")
            succeeded += 1
          else
            UI.say_error("Failed to remove #{label}")
            failed += 1
          end

          puts if index < selections.length - 1
        end

        puts
        UI.say_status("Done: #{succeeded} removed#{", #{failed} failed" if failed > 0}")
      end
    end
  end
end
