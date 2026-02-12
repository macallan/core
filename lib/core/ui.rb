module Core
  module UI
    # Lazy-load TTY gems — degrade to plain text if unavailable
    GEMS_AVAILABLE = begin
      require 'pastel'
      require 'tty-spinner'
      require 'tty-prompt'

      # Add vim keybindings to TTY::Prompt
      module VimKeybindings
        def keypress(event)
          case event.value
          when 'j'
            keydown
          when 'k'
            keyup
          when 'g'
            if @last_key == 'g'
              @active = 1
              @last_key = nil
            else
              @last_key = 'g'
            end
          when 'G'
            @active = choices.length
          else
            super
          end
        end
      end

      # Live-update choices on List while user is in the prompt
      module UpdatableList
        def initialize(prompt, **options)
          @update_queue = options.delete(:update_queue)
          super(prompt, **options)
        end

        def keypress(event)
          check_for_updates if @update_queue
          super
        end

        private

        def check_for_updates
          new_choices = @update_queue.pop(true) rescue nil
          return unless new_choices

          apply_update(new_choices)
        end

        def apply_update(new_choices)
          # Remember current selection by value
          current_value = @active ? @choices[@active - 1]&.value : nil

          @choices = TTY::Prompt::Choices.new(new_choices)

          # Restore selection position
          new_active = nil
          if current_value
            @choices.each_with_index do |choice, idx|
              if choice.value == current_value
                new_active = idx + 1
                break
              end
            end
          end

          @active = new_active || 1

          # Remove "(refreshing...)" suffix from question
          @question = @question.sub(/ \(refreshing\.\.\.\)$/, '')
        end
      end

      # Prepend vim keybindings to List classes
      TTY::Prompt::List.prepend(VimKeybindings)
      TTY::Prompt::MultiList.prepend(VimKeybindings) if defined?(TTY::Prompt::MultiList)

      # Prepend live-update support to List
      TTY::Prompt::List.prepend(UpdatableList)

      true
    rescue LoadError
      false
    end

    class << self
      # ── Color helpers ──────────────────────────────────────────────

      def success(text)
        pastel&.green(text) || text
      end

      def error(text)
        pastel&.red(text) || text
      end

      def dim(text)
        pastel&.dim(text) || text
      end

      def bold(text)
        pastel&.bold(text) || text
      end

      def warning(text)
        pastel&.yellow(text) || text
      end

      def ci_icon(status)
        case status
        when :success then pastel ? pastel.green('✓') : '✓'
        when :failure then pastel ? pastel.red('✗') : '✗'
        when :pending then pastel ? pastel.yellow('⋯') : '⋯'
        else ' '
        end
      end

      # ── Output helpers ─────────────────────────────────────────────

      def say_ok(text)
        puts "#{ci_icon(:success)} #{text}"
      end

      def say_error(text)
        prefix = pastel ? pastel.red('Error:') : 'Error:'
        $stderr.puts "#{prefix} #{text}"
      end

      def say_status(text)
        puts dim(text)
      end

      # ── Spinner ────────────────────────────────────────────────────

      def spin(message)
        unless GEMS_AVAILABLE
          $stderr.puts "#{message}..."
          return yield
        end

        spinner = TTY::Spinner.new(
          "#{dim(':spinner')} #{message}",
          format: :dots,
          clear: true,
          output: $stderr
        )
        spinner.auto_spin

        result = yield

        spinner.success(pastel ? pastel.green(' done') : ' done')
        result
      rescue => e
        spinner&.error(pastel ? pastel.red(' failed') : ' failed')
        raise
      end

      # ── Interactive prompts ────────────────────────────────────────

      def gems_available?
        GEMS_AVAILABLE
      end

      def main_menu
        prompt.select('What would you like to do?', per_page: 12) do |menu|
          menu.choice 'List PRs',           :list_prs
          menu.choice 'Start Work',        :start_work
          menu.choice 'Start Review',      :start_review
          menu.choice 'Finish Review',      :finish_review
          menu.choice 'Generate Context',   :context
          menu.choice 'Goto Worktree',      :goto
          menu.choice 'List Worktrees',     :list_worktrees
          menu.choice 'List Contexts',      :list_contexts
          menu.choice 'Manage Repos  →',    :manage_repos
          menu.choice 'Manage Authors →',   :manage_authors
          menu.choice 'Help',               :help
          menu.choice 'Quit',               :quit
        end
      end

      def repo_menu
        prompt.select('Repository management:') do |menu|
          menu.choice 'Add Repo',    :add_repo
          menu.choice 'List Repos',  :list_repos
          menu.choice 'Remove Repo', :remove_repo
          menu.choice '← Back',      :back
        end
      end

      def author_menu
        prompt.select('Author management:') do |menu|
          menu.choice 'Add Author',    :add_author
          menu.choice 'List Authors',  :list_authors
          menu.choice 'Remove Author', :remove_author
          menu.choice '← Back',        :back
        end
      end

      def ask(question)
        prompt.ask(question)
      end

      def build_pr_choices(prs_by_repo)
        choices = []

        prs_by_repo.each do |repo, prs|
          prs.each do |pr|
            draft = pr[:draft] ? ' [DRAFT]' : ''

            # Review status indicator
            review_indicator = case pr[:review_status]
            when :approved then ' ✅'
            when :changes_requested then ' ❌'
            when :pending then ' ⚪'
            else ''
            end

            # Comment count
            comments = pr[:comment_count] > 0 ? " 💬 #{pr[:comment_count]}" : ''

            label = "##{pr[:number]}  #{pr[:title]}#{draft}#{review_indicator}#{comments}  (@#{pr[:author]}, ↻ #{pr[:updated_age]})"
            choices << { name: label, value: { repo: repo, number: pr[:number] } }
          end
        end

        choices
      end

      def select_pr(prs_by_repo, update_queue: nil)
        choices = build_pr_choices(prs_by_repo)

        question = 'Select a PR to review:'
        opts = { per_page: 15 }

        if update_queue
          question += ' (refreshing...)'
          opts[:update_queue] = update_queue
        end

        prompt.select(question, choices, **opts)
      end

      def select_worktree(worktrees, multi: false)
        choices = worktrees.map do |wt|
          label = "#{wt['repo']}  PR ##{wt['pr_number']}  (#{wt['branch']})"
          { name: label, value: wt }
        end

        if multi
          prompt.multi_select('Select worktrees (Space to select, Enter to confirm):', choices, per_page: 15)
        else
          prompt.select('Select a worktree:', choices)
        end
      end

      private

      def pastel
        return nil unless GEMS_AVAILABLE
        @pastel ||= Pastel.new(enabled: $stdout.tty?)
      end

      def prompt
        @prompt ||= TTY::Prompt.new(
          symbols: { marker: '›' },
          active_color: :cyan,
          help_color: :dim,
          enable_color: true
        )
      end
    end
  end
end
