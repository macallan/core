require 'json'
require 'open3'

module Core
  class GitHubClient
    class AuthenticationError < StandardError; end
    class NotInstalledError < StandardError; end

    attr_reader :username

    def initialize
      check_gh_installed
      check_gh_authenticated
      @username = current_user
    end

    def current_user
      @current_user ||= begin
        stdout, stderr, status = Open3.capture3('gh', 'api', 'user')
        raise AuthenticationError, "Failed to get current user" unless status.success?
        JSON.parse(stdout)['login']
      end
    end

    def user_team_slugs
      @user_team_slugs ||= begin
        stdout, stderr, status = Open3.capture3('gh', 'api', 'user/teams', '--paginate')
        return [] unless status.success?

        teams = JSON.parse(stdout)
        return [] unless teams.is_a?(Array)

        teams.map { |t| t['slug'] }
      rescue JSON::ParserError
        []
      end
    end

    def pulls(repo, state: 'open')
      stdout, stderr, status = Open3.capture3('gh', 'api', "repos/#{repo}/pulls?state=#{state}&per_page=100")

      unless status.success?
        if stderr.include?('Not Found')
          warn "Repository not found: #{repo}"
          return []
        end
        raise "GitHub API error: #{stderr}"
      end

      JSON.parse(stdout)
    rescue JSON::ParserError => e
      warn "Failed to parse response for #{repo}: #{e.message}"
      []
    end

    def combined_status(repo, ref)
      stdout, stderr, status = Open3.capture3('gh', 'api', "repos/#{repo}/commits/#{ref}/status")
      return nil unless status.success?

      JSON.parse(stdout)
    rescue JSON::ParserError
      nil
    end

    def pr(repo, number)
      api("repos/#{repo}/pulls/#{number}")
    end

    def pr_files(repo, number)
      api("repos/#{repo}/pulls/#{number}/files")
    end

    def pr_comments(repo, number, limit: 10)
      comments = api("repos/#{repo}/pulls/#{number}/comments")
      return [] unless comments.is_a?(Array)
      comments.last(limit)
    end

    def pr_reviews(repo, number)
      api("repos/#{repo}/pulls/#{number}/reviews")
    end

    private

    def api(endpoint)
      stdout, stderr, status = Open3.capture3('gh', 'api', endpoint)

      unless status.success?
        if stderr.include?('Not Found')
          warn "Not found: #{endpoint}"
          return nil
        end
        raise "GitHub API error: #{stderr}"
      end

      JSON.parse(stdout)
    rescue JSON::ParserError => e
      warn "Failed to parse response for #{endpoint}: #{e.message}"
      nil
    end

    def check_gh_installed
      stdout, stderr, status = Open3.capture3('which', 'gh')
      if stdout.strip.empty?
        raise NotInstalledError, "GitHub CLI (gh) is not installed. Install it from https://cli.github.com/"
      end
    end

    def check_gh_authenticated
      stdout, stderr, status = Open3.capture3('gh', 'auth', 'status')
      unless status.success?
        raise AuthenticationError, "GitHub CLI not authenticated. Run `gh auth login` first"
      end
    end
  end
end
