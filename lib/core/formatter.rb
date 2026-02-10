require_relative 'config'
require_relative 'ui'

module Core
  class Formatter
    CI_ICONS = {
      success: '✓',
      failure: '✗',
      pending: '⋯',
      unknown: ' '
    }

    REVIEW_ICONS = {
      approved: '✓',
      changes_requested: '✗',
      pending: '○'
    }

    def self.format_prs(prs_by_repo)
      return "No PRs need attention" if prs_by_repo.empty?

      tracked_authors = Config.authors
      output = ["PRs needing attention:\n"]
      total_count = 0

      prs_by_repo.each do |repo, prs|
        output << "\n#{UI.bold(repo)}"

        prs.each do |pr|
          output << format_pr_line(pr, tracked_authors)
          total_count += 1
        end
      end

      output << UI.dim("\nTotal: #{total_count} #{total_count == 1 ? 'PR' : 'PRs'}")

      # Add legend if there are tracked authors
      unless tracked_authors.empty?
        output << UI.dim("\n* = Tracked author")
      end

      output.join("\n")
    end

    def self.format_pr_line(pr, tracked_authors = [])
      draft_marker = pr[:draft] ? '[DRAFT] ' : ''

      # Add * indicator for tracked authors
      is_tracked = tracked_authors.include?(pr[:author])
      author_indicator = is_tracked ? '*' : ''

      # Pad BEFORE applying color to avoid ANSI-breaking alignment
      number_str = "##{pr[:number]}".ljust(7)
      ci_plain = CI_ICONS[pr[:ci_status]]
      ci_status_str = "[#{ci_plain} CI] ".ljust(7)

      # Review status
      review_plain = REVIEW_ICONS[pr[:review_status]]
      review_str = "[#{review_plain} Rev] ".ljust(8)

      # Comment count
      comment_str = pr[:comment_count] > 0 ? "💬 #{pr[:comment_count]} ".ljust(6) : ""

      title_str = truncate(draft_marker + pr[:title], 32).ljust(34)
      author_str = "@#{pr[:author]}#{author_indicator}".ljust(13)
      updated_str = "↻ #{pr[:updated_age]}"

      # Apply color AFTER padding
      number_str = UI.dim(number_str)
      ci_status_str = "[#{UI.ci_icon(pr[:ci_status])} CI] " + ' ' * [0, 7 - "[#{ci_plain} CI] ".length].max

      # Color review status
      case pr[:review_status]
      when :approved
        review_str = "[#{UI.success(review_plain)} Rev]  "
      when :changes_requested
        review_str = "[#{UI.error(review_plain)} Rev]  "
      when :pending
        review_str = "[#{UI.dim(review_plain)} Rev]  "
      end

      if pr[:draft]
        title_str = UI.warning(title_str)
      end
      author_str = is_tracked ? UI.success(author_str) : author_str
      updated_str = UI.dim(updated_str)

      "  #{number_str}#{ci_status_str}#{review_str}#{comment_str}#{title_str}#{author_str}#{updated_str}"
    end

    def self.truncate(string, max_length)
      if string.length > max_length
        string[0...max_length - 3] + '...'
      else
        string
      end
    end

    def self.format_file_changes(files)
      return "No files changed" if files.empty?

      files.map do |file|
        additions = file['additions'] || 0
        deletions = file['deletions'] || 0
        status = file['status'] || 'modified'

        "- #{file['filename']} [#{status}] (+#{additions}, -#{deletions})"
      end.join("\n")
    end

    def self.format_comments(comments)
      return "No comments yet" if comments.empty?

      comments.map do |comment|
        author = comment['user']['login']
        body = comment['body'][0..100] # Truncate long comments
        created = Time.parse(comment['created_at']).strftime('%Y-%m-%d')

        "**@#{author}** (#{created}): #{body}..."
      end.join("\n\n")
    rescue
      "Error formatting comments"
    end
  end
end
