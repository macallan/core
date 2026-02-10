module Core
  module Commands
    class ListRepos < Base
      def run
        repos = Config.repos
        if repos.empty?
          puts "No repositories configured."
          UI.say_status("Add repositories with: core add-repo owner/repo")
        else
          puts "Tracked repositories:"
          repos.each { |repo| puts "  - #{repo}" }
        end
      end
    end
  end
end
