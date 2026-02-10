module Core
  module Commands
    class ListContexts < Base
      def run
        repo = @args.shift

        require_relative '../context_generator'
        generator = ContextGenerator.new(client)

        contexts = generator.list_contexts(repo)

        if contexts.empty?
          if repo
            puts "No saved contexts found for #{repo}"
          else
            puts "No saved contexts found."
          end
          UI.say_status("Generate a context with: core context PR_NUMBER --repo owner/repo")
        else
          puts "Saved PR contexts:"
          contexts.each do |context|
            display_path = context.sub(File.expand_path('~/.core/contexts/'), '').sub(/^\//, '')
            puts "  #{display_path}"
          end
        end
      end
    end
  end
end
