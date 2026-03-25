module Core
  module Commands
    class MyPrs < Base
      def run
        repos = Config.repos
        if repos.empty?
          UI.say_error("No tracked repositories. Add one with: core add-repo owner/repo")
          exit 1
        end

        all_prs = []

        UI.spin("Fetching your open PRs") do
          username = client.username

          repos.each do |repo|
            prs = client.pulls(repo)
            prs.each do |pr|
              next unless pr['user']['login'] == username

              all_prs << {
                repo: repo,
                number: pr['number'],
                title: pr['title'],
                branch: pr['head']['ref'],
                draft: pr['draft'],
              }
            end
          end
        end

        if all_prs.empty?
          UI.say_status("No open PRs found authored by you")
          return
        end

        selected = UI.select_my_prs(all_prs)
        return if selected.empty?

        selected.each do |pr|
          puts
          UI.say_status("Setting up #{pr[:repo]}##{pr[:number]}: #{pr[:title]}")
          Commands::Work.new(
            args: [pr[:branch]],
            options: @options.merge(repo: pr[:repo])
          ).run
        end
      end
    end
  end
end
