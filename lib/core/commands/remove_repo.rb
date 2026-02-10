module Core
  module Commands
    class RemoveRepo < Base
      def run
        repo = @args.shift

        unless repo
          UI.say_error("Missing repository argument")
          puts "Usage: core remove-repo owner/repo"
          exit 1
        end

        if Config.remove_repo(repo)
          UI.say_ok("Removed repository: #{repo}")
        else
          puts "Repository not found: #{repo}"
          exit 1
        end
      end
    end
  end
end
