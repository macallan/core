module Core
  module Commands
    class RemoveAuthor < Base
      def run
        username = @args.shift

        unless username
          UI.say_error("Missing username argument")
          puts "Usage: core remove-author USERNAME"
          exit 1
        end

        if Config.remove_author(username)
          UI.say_ok("Removed author: #{username}")
        else
          puts "Author not found: #{username}"
          exit 1
        end
      end
    end
  end
end
