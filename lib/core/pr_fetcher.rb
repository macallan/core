require 'time'

module Core
  class PRFetcher
    attr_reader :client, :username

    def initialize(client)
      @client = client
      @username = client.username
      @tracked_authors = Config.authors
      @user_team_slugs = client.user_team_slugs
    end

    def fetch_prs_needing_attention(repos, refresh: false)
      prs_by_repo = {}

      repos.each do |repo|
        last_checked = refresh ? nil : Config.get_last_checked(repo)
        pulls = client.pulls(repo)

        needs_attention = pulls.select do |pr|
          pr_needs_attention?(pr, last_checked)
        end

        if needs_attention.any?
          prs_by_repo[repo] = needs_attention.map do |pr|
            enhance_pr_data(repo, pr)
          end
        end

        # Update last_checked timestamp
        Config.update_last_checked(repo, Time.now)
      end

      prs_by_repo
    end

    private

    def pr_needs_attention?(pr, last_checked)
      # Filter out PRs older than 2 weeks
      created_at = Time.parse(pr['created_at'])
      two_weeks_ago = Time.now - (14 * 24 * 60 * 60)
      return false if created_at < two_weeks_ago

      author = pr.dig('user', 'login')

      # Check if author is in tracked authors list (always show)
      return true if @tracked_authors.include?(author)

      # Check if user is requested reviewer
      requested_reviewers = pr['requested_reviewers'] || []
      is_reviewer = requested_reviewers.any? { |r| r['login'] == username }
      return true if is_reviewer

      # Check if any of the user's teams are requested for review
      requested_teams = pr['requested_teams'] || []
      is_team_reviewer = requested_teams.any? { |t| @user_team_slugs.include?(t['slug']) }
      return true if is_team_reviewer

      # Check if user is assigned
      assignees = pr['assignees'] || []
      is_assignee = assignees.any? { |a| a['login'] == username }
      return true if is_assignee

      # Check if updated since last check (only for PRs where user is involved)
      if last_checked && (is_reviewer || is_assignee)
        updated_at = Time.parse(pr['updated_at'])
        return true if updated_at > last_checked
      end

      false
    end

    def enhance_pr_data(repo, pr)
      # Fetch full PR details to get comment counts
      full_pr = client.pr(repo, pr['number'])

      status = get_ci_status(repo, pr)
      age = calculate_age(pr['created_at'])
      updated_age = calculate_age(pr['updated_at'])
      review_status = get_review_status(repo, pr)

      # Get comment counts from full PR details
      comment_count = 0
      if full_pr
        comment_count = (full_pr['comments'] || 0) + (full_pr['review_comments'] || 0)
      end

      {
        number: pr['number'],
        title: pr['title'],
        author: pr['user']['login'],
        url: pr['html_url'],
        created_at: pr['created_at'],
        updated_at: pr['updated_at'],
        age: age,
        updated_age: updated_age,
        ci_status: status,
        review_status: review_status,
        comment_count: comment_count,
        draft: pr['draft'] || false,
        mergeable_state: pr['mergeable_state']
      }
    end

    def get_ci_status(repo, pr)
      head = pr['head']
      return :unknown unless head && head['sha']

      status = client.combined_status(repo, head['sha'])
      return :unknown unless status

      case status['state']
      when 'success'
        :success
      when 'failure'
        :failure
      when 'pending'
        :pending
      else
        :unknown
      end
    rescue => e
      :unknown
    end

    def get_review_status(repo, pr)
      reviews = client.pr_reviews(repo, pr['number'])
      return :pending unless reviews && reviews.is_a?(Array) && reviews.any?

      # Get the latest review from each reviewer
      latest_reviews = {}
      reviews.each do |review|
        reviewer = review['user']['login']
        review_time = Time.parse(review['submitted_at'])

        if !latest_reviews[reviewer] || Time.parse(latest_reviews[reviewer]['submitted_at']) < review_time
          latest_reviews[reviewer] = review
        end
      end

      # Check for approvals and changes requested
      has_changes_requested = latest_reviews.values.any? { |r| r['state'] == 'CHANGES_REQUESTED' }
      has_approved = latest_reviews.values.any? { |r| r['state'] == 'APPROVED' }

      if has_changes_requested
        :changes_requested
      elsif has_approved
        :approved
      else
        :pending
      end
    rescue => e
      :pending
    end

    def calculate_age(created_at)
      time = created_at.is_a?(String) ? Time.parse(created_at) : created_at
      seconds = Time.now - time

      case seconds
      when 0..3599
        minutes = (seconds / 60).to_i
        "#{minutes} #{minutes == 1 ? 'minute' : 'minutes'} ago"
      when 3600..86399
        hours = (seconds / 3600).to_i
        "#{hours} #{hours == 1 ? 'hour' : 'hours'} ago"
      when 86400..604799
        days = (seconds / 86400).to_i
        "#{days} #{days == 1 ? 'day' : 'days'} ago"
      else
        weeks = (seconds / 604800).to_i
        "#{weeks} #{weeks == 1 ? 'week' : 'weeks'} ago"
      end
    end
  end
end
