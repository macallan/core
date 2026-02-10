module Core
  module Commands
    class AddRepo < Base
      def run
        repo = @args.shift

        unless repo
          UI.say_error("Missing repository argument")
          puts "Usage: core add-repo owner/repo"
          exit 1
        end

        if repo =~ /^[\w-]+\/[\w-]+$/
          Config.add_repo(repo)
          UI.say_ok("Added repository: #{repo}")
        else
          UI.say_error("Invalid repository format. Use: owner/repo")
          exit 1
        end
      end
    end
  end
end
