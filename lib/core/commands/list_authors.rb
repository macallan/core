module Core
  module Commands
    class ListAuthors < Base
      def run
        authors = Config.authors
        if authors.empty?
          puts "No authors configured."
          UI.say_status("Add authors with: core add-author USERNAME")
        else
          puts "Tracked authors:"
          authors.each { |author| puts "  - #{author}" }
        end
      end
    end
  end
end
