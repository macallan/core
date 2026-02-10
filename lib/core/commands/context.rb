module Core
  module Commands
    class Context < Base
      def run
        pr_number = @args.shift&.to_i

        unless pr_number && pr_number > 0
          UI.say_error("Missing PR number argument")
          puts "Usage: core context PR_NUMBER [--repo owner/repo]"
          exit 1
        end

        repo = determine_repo_from_args_or_prompt

        if repo.nil?
          UI.say_error("Please specify repository with --repo or run from a git repository")
          exit 1
        end

        require_relative '../context_generator'
        generator = ContextGenerator.new(client)

        file_path = UI.spin("Fetching PR data for #{repo} ##{pr_number}") do
          generator.generate(repo, pr_number)
        end

        if file_path.nil?
          UI.say_error("Could not fetch PR ##{pr_number} from #{repo}")
          exit 1
        end

        UI.say_ok("Context file saved: #{file_path}")

        if ENV['EDITOR']
          UI.say_status("Opening in $EDITOR...")
          system(ENV['EDITOR'], file_path)
        else
          UI.say_status("Tip: Set $EDITOR environment variable to auto-open in your editor")
        end
      end
    end
  end
end
