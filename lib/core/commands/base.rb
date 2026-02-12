module Core
  module Commands
    class Base
      def initialize(args:, options:)
        @args = args
        @options = options
      end

      def run
        raise NotImplementedError, "#{self.class}#run must be implemented"
      end

      private

      def client
        @client ||= GitHubClient.new
      end

      def determine_repo_from_args_or_prompt
        return @options[:repo] if @options[:repo]

        detect_repo_from_git
      end

      def build_window_name(pr_number, pr_title)
        return pr_number.to_s unless pr_title

        slug = pr_title.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
        slug = slug[0, 25].chomp('-')
        "#{pr_number}:#{slug}"
      end

      def detect_repo_from_git
        output = `git config --get remote.origin.url 2>/dev/null`.strip
        return nil if output.empty?

        if output =~ /github\.com[:|\/]([^\/]+\/[^\/\.]+)/
          $1.sub(/\.git$/, '')
        end
      end

      def handle_tmux_window_creation(worktree_path, pr_number, pr_title: nil)
        require_relative '../tmux_manager'

        repo = determine_repo_from_args_or_prompt
        tmux = TmuxManager.new(repo: repo)

        return false unless tmux.in_tmux?

        window_name = build_window_name(pr_number, pr_title)

        begin
          result = tmux.create_window(worktree_path, window_name)

          if @options[:debug]
            UI.say_ok("Created tmux window '#{result[:window_name]}' in session '#{result[:session]}' with #{result[:panes]} panes (#{result[:split]} split)")
          end

          true
        rescue TmuxManager::TmuxError => e
          if @options[:debug]
            puts UI.warning("Warning: Could not create tmux window: #{e.message}")
          end
          false
        end
      end
    end
  end
end
