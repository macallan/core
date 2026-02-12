require 'optparse'
require_relative 'config'
require_relative 'github_client'
require_relative 'pr_fetcher'
require_relative 'formatter'
require_relative 'ui'
require_relative 'pr_cache'
require_relative 'commands/base'
require_relative 'commands/list'
require_relative 'commands/add_repo'
require_relative 'commands/list_repos'
require_relative 'commands/remove_repo'
require_relative 'commands/add_author'
require_relative 'commands/remove_author'
require_relative 'commands/list_authors'
require_relative 'commands/context'
require_relative 'commands/list_contexts'
require_relative 'commands/start_review'
require_relative 'commands/start_work'
require_relative 'commands/finish_review'
require_relative 'commands/list_worktrees'
require_relative 'commands/goto'

module Core
  class CLI
    COMMANDS = {
      'list'           => Commands::List,
      'add-repo'       => Commands::AddRepo,
      'list-repos'     => Commands::ListRepos,
      'remove-repo'    => Commands::RemoveRepo,
      'add-author'     => Commands::AddAuthor,
      'remove-author'  => Commands::RemoveAuthor,
      'list-authors'   => Commands::ListAuthors,
      'context'        => Commands::Context,
      'list-contexts'  => Commands::ListContexts,
      'start-review'   => Commands::StartReview,
      'start-work'     => Commands::StartWork,
      'finish-review'  => Commands::FinishReview,
      'list-worktrees' => Commands::ListWorktrees,
      'goto'           => Commands::Goto,
    }.freeze

    def initialize(args)
      @args = args
      @options = { refresh: false }
      @action = nil
    end

    def run
      parse_options

      command = @args.shift

      if command.nil?
        if $stdin.tty? && UI.gems_available?
          interactive_mode
        else
          Commands::List.new(args: @args, options: @options).run
        end
      elsif COMMANDS.key?(command)
        COMMANDS[command].new(args: @args, options: @options).run
      else
        show_help(command)
      end
    rescue GitHubClient::NotInstalledError => e
      UI.say_error(e.message)
      exit 1
    rescue GitHubClient::AuthenticationError => e
      UI.say_error(e.message)
      exit 1
    rescue => e
      UI.say_error(e.message)
      puts e.backtrace if @options[:debug]
      exit 1
    end

    private

    def parse_options
      OptionParser.new do |opts|
        opts.banner = "Usage: core [command] [options]"
        opts.separator ""
        opts.separator "Commands:"
        opts.separator "    list                      List PRs needing attention (default)"
        opts.separator ""
        opts.separator "  Repository management:"
        opts.separator "    add-repo REPO             Add a repository to track (format: owner/repo)"
        opts.separator "    list-repos                List all tracked repositories"
        opts.separator "    remove-repo REPO          Remove a repository from tracking"
        opts.separator ""
        opts.separator "  Author management:"
        opts.separator "    add-author USERNAME       Add an author to track"
        opts.separator "    remove-author USERNAME    Remove an author from tracking"
        opts.separator "    list-authors              List all tracked authors"
        opts.separator ""
        opts.separator "  PR context and review:"
        opts.separator "    context PR_NUMBER         Generate/update context file for a PR"
        opts.separator "    list-contexts [REPO]      List all saved PR contexts"
        opts.separator "    start-work BRANCH_NAME    Create a worktree for new work on a branch"
        opts.separator "    start-review [PR_NUMBER]  Start reviewing a PR (interactive picker if no number given)"
        opts.separator "    finish-review [PR_NUMBER] Clean up worktree after finishing review (interactive picker if no number given)"
        opts.separator "    list-worktrees [REPO]     List active PR worktrees"
        opts.separator "    goto [PR_NUMBER]          Go to a PR worktree (interactive picker if no number given)"
        opts.separator ""
        opts.separator "Options:"

        opts.on("-r", "--refresh", "Ignore last_checked timestamp") do
          @options[:refresh] = true
        end

        opts.on("--base BRANCH", "Base branch for start-work (default: auto-detect)") do |branch|
          @options[:base] = branch
        end

        opts.on("--repo REPO", "Specify repository for operations") do |repo|
          @options[:repo] = repo
        end

        opts.on("--debug", "Show debug information") do
          @options[:debug] = true
        end

        opts.on("-h", "--help", "Show this help message") do
          puts opts
          exit 0
        end
      end.parse!(@args)
    end

    # ── Interactive mode ───────────────────────────────────────────────

    def interactive_mode
      loop do
        choice = UI.main_menu

        case choice
        when :list_prs       then Commands::List.new(args: [], options: @options).run
        when :start_work     then interactive_start_work
        when :start_review   then interactive_start_review
        when :finish_review  then interactive_finish_review
        when :context        then interactive_context
        when :goto           then interactive_goto
        when :list_worktrees then Commands::ListWorktrees.new(args: [], options: @options).run
        when :list_contexts  then Commands::ListContexts.new(args: [], options: @options).run
        when :manage_repos   then interactive_manage_repos
        when :manage_authors then interactive_manage_authors
        when :help           then show_help
        when :quit           then break
        end

        puts
      end
    rescue Interrupt, TTY::Reader::InputInterrupt
      puts
      exit 0
    end

    def interactive_start_work
      branch = UI.ask('Branch name:')
      return unless branch && !branch.strip.empty?

      Commands::StartWork.new(args: [branch], options: @options).run
    end

    def interactive_start_review
      Commands::StartReview.new(args: [], options: @options).run
    end

    def interactive_finish_review
      Commands::FinishReview.new(args: [], options: @options).run
    end

    def interactive_context
      pr = UI.ask('PR number:')&.to_i
      return unless pr && pr > 0

      Commands::Context.new(args: [pr.to_s], options: @options).run
    end

    def interactive_goto
      Commands::Goto.new(args: [], options: @options).run
    end

    def interactive_manage_repos
      loop do
        choice = UI.repo_menu
        case choice
        when :add_repo
          repo = UI.ask('Repository (owner/repo):')
          Commands::AddRepo.new(args: [repo], options: @options).run if repo
        when :list_repos
          Commands::ListRepos.new(args: [], options: @options).run
        when :remove_repo
          repo = UI.ask('Repository to remove (owner/repo):')
          Commands::RemoveRepo.new(args: [repo], options: @options).run if repo
        when :back
          break
        end
        puts
      end
    end

    def interactive_manage_authors
      loop do
        choice = UI.author_menu
        case choice
        when :add_author
          author = UI.ask('GitHub username:')
          Commands::AddAuthor.new(args: [author], options: @options).run if author
        when :list_authors
          Commands::ListAuthors.new(args: [], options: @options).run
        when :remove_author
          author = UI.ask('Username to remove:')
          Commands::RemoveAuthor.new(args: [author], options: @options).run if author
        when :back
          break
        end
        puts
      end
    end

    def show_help(command = nil)
      if command
        puts "Unknown command: #{command}"
      end
      puts "Run 'core --help' for usage information"
      exit 1
    end
  end
end
