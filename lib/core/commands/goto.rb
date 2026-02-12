module Core
  module Commands
    class Goto < Base
      def run
        pr_number = @args.shift&.to_i

        require_relative '../worktree_manager'
        manager = WorktreeManager.new(client)

        unless pr_number && pr_number > 0
          worktrees = manager.list
          flat = worktrees.flat_map do |repo_name, wt_list|
            (wt_list || []).map { |wt| wt.merge('repo' => repo_name) }
          end

          if flat.empty?
            puts "No active worktrees."
            return
          end

          if $stdin.tty? && UI.gems_available?
            selected = UI.select_worktree(flat)
            return unless selected

            pr_number = selected['pr_number']
            path = selected['path']
          else
            ListWorktrees.new(args: [], options: @options).run
            return
          end
        else
          repo = determine_repo_from_args_or_prompt

          if repo.nil?
            UI.say_error("Please specify repository with --repo or run from a git repository")
            exit 1
          end

          path = manager.goto(repo, pr_number)

          unless path
            UI.say_error("No active worktree found for PR ##{pr_number}")
            exit 1
          end
        end

        goto_repo = repo || selected&.dig('repo')
        pr_title = goto_repo ? client.pr(goto_repo, pr_number)&.dig('title') : nil
        tmux_created = handle_tmux_window_creation(path, pr_number, pr_title: pr_title)
        puts "cd #{path}" unless tmux_created
      end
    end
  end
end
