module Core
  module Commands
    class AddAuthor < Base
      def run
        username = @args.shift

        unless username
          UI.say_error("Missing username argument")
          puts "Usage: core add-author USERNAME"
          exit 1
        end

        if username =~ /^[a-zA-Z0-9_-]+$/
          Config.add_author(username)
          UI.say_ok("Added author: #{username}")
        else
          UI.say_error("Invalid username format")
          exit 1
        end
      end
    end
  end
end
