module Core
  module Commands
    class ListWorktrees < Base
      def run
        repo = @args.shift
        repo ||= determine_repo_from_args_or_prompt if @options[:repo]

        require_relative '../worktree_manager'
        manager = WorktreeManager.new(client)

        worktrees = manager.list(repo)

        if worktrees.empty? || worktrees.values.all? { |wts| wts.nil? || wts.empty? }
          puts "No active worktrees found."
        else
          puts "Active PR worktrees:\n\n"

          worktrees.each do |repo_name, wt_list|
            next if wt_list.nil? || wt_list.empty?

            puts UI.bold(repo_name)
            wt_list.each do |wt|
              pr_number = wt['pr_number']
              path = wt['path']
              puts "  PR ##{pr_number}: #{path}"
            end
            puts
          end

          total = worktrees.values.flatten.compact.size
          puts UI.dim("Total: #{total} active review#{'s' if total != 1}")
        end
      end
    end
  end
end
