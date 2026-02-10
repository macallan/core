module Core
  module Commands
    class List < Base
      def run
        repos = Config.repos

        if repos.empty?
          puts "No repositories configured."
          UI.say_status("Add repositories with: core add-repo owner/repo")
          UI.say_status("Or edit ~/.core.yml directly")
          exit 1
        end

        cached = PRCache.read

        if cached && !@options[:refresh]
          puts "\n" + Formatter.format_prs(cached[:prs_by_repo])
          UI.say_status("(cached from #{PRCache.calculate_age(cached[:cached_at])})")

          # Fire-and-forget background refresh for next run
          PRCache.refresh_in_background do
            PRFetcher.new(client).fetch_prs_needing_attention(repos, refresh: false)
          end
        else
          fetcher = PRFetcher.new(client)

          prs_by_repo = UI.spin("Fetching PRs from #{repos.size} #{repos.size == 1 ? 'repository' : 'repositories'}") do
            fetcher.fetch_prs_needing_attention(repos, refresh: @options[:refresh])
          end

          PRCache.write(prs_by_repo)
          puts "\n" + Formatter.format_prs(prs_by_repo)
        end
      end
    end
  end
end
