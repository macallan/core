require 'fileutils'
require 'time'
require_relative 'config'

module Core
  class ContextGenerator
    CONTEXT_DIR = File.expand_path('~/.core/contexts')
    NOTES_MARKER = "## My Review Notes"

    def initialize(client)
      @client = client
    end

    def generate(repo, pr_number)
      pr_data = fetch_pr_data(repo, pr_number)

      return nil unless pr_data

      markdown = build_markdown(pr_data)
      file_path = context_file_path(repo, pr_number)
      save_context(file_path, markdown)

      file_path
    end

    def list_contexts(repo = nil)
      return [] unless Dir.exist?(CONTEXT_DIR)

      pattern = if repo
        owner, name = repo.split('/')
        File.join(CONTEXT_DIR, owner, name, 'PR-*.md')
      else
        File.join(CONTEXT_DIR, '**', 'PR-*.md')
      end

      Dir.glob(pattern).sort
    end

    def context_exists?(repo, pr_number)
      File.exist?(context_file_path(repo, pr_number))
    end

    private

    def fetch_pr_data(repo, pr_number)
      pr = @client.pr(repo, pr_number)
      return nil unless pr

      files = @client.pr_files(repo, pr_number) || []
      comments = @client.pr_comments(repo, pr_number) || []
      ci_status = @client.combined_status(repo, pr['head']['sha']) if pr['head']

      {
        pr: pr,
        files: files,
        comments: comments,
        ci_status: ci_status,
        repo: repo
      }
    end

    def build_markdown(data)
      pr = data[:pr]
      files = data[:files]
      comments = data[:comments]
      ci_status = data[:ci_status]
      repo = data[:repo]

      draft_status = pr['draft'] ? 'true' : 'false'
      created_at = format_date(pr['created_at'])
      updated_at = format_date(pr['updated_at'])

      markdown = <<~MD
        # PR ##{pr['number']}: #{pr['title']}

        **Repository**: #{repo}
        **Author**: @#{pr['user']['login']}
        **Status**: #{pr['state']} (Draft: #{draft_status})
        **Created**: #{created_at}
        **Updated**: #{updated_at}
        **URL**: #{pr['html_url']}

        ## Description

        #{pr['body'] || '_No description provided_'}

        ## Files Changed (#{files.size} files)

        #{format_files(files)}

        ## CI Status

        #{format_ci_status(ci_status)}

        ## Review Comments (#{comments.size} comments)

        #{format_comments(comments)}

        ---

        #{NOTES_MARKER}

        <!-- Add your notes below -->

        ### First Review - #{Time.now.strftime('%Y-%m-%d')}


      MD

      markdown
    end

    def format_date(date_string)
      return 'N/A' unless date_string
      Time.parse(date_string).strftime('%Y-%m-%d %H:%M:%S')
    rescue
      date_string
    end

    def format_files(files)
      return '_No files changed_' if files.empty?

      if files.size > 50
        formatted = files.first(50).map { |f| format_file_line(f) }
        formatted << "\n_...and #{files.size - 50} more files_"
        formatted.join("\n")
      else
        files.map { |f| format_file_line(f) }.join("\n")
      end
    end

    def format_file_line(file)
      additions = file['additions'] || 0
      deletions = file['deletions'] || 0
      status = file['status'] || 'modified'

      "- #{file['filename']} [#{status}] (+#{additions}, -#{deletions})"
    end

    def format_ci_status(ci_status)
      return '_No CI status available_' unless ci_status

      state = ci_status['state'] || 'unknown'
      statuses = ci_status['statuses'] || []
      total_count = ci_status['total_count'] || 0

      icon = case state
             when 'success' then '✓'
             when 'failure' then '✗'
             when 'pending' then '⋯'
             else '?'
             end

      if total_count == 0
        "_No CI checks configured_"
      else
        summary = "#{icon} #{state.capitalize} (#{total_count} checks)"

        if statuses.any?
          summary += "\n\n"
          summary += statuses.map do |s|
            s_icon = case s['state']
                     when 'success' then '✓'
                     when 'failure' then '✗'
                     when 'pending' then '⋯'
                     else '?'
                     end
            "- #{s_icon} #{s['context']}: #{s['description'] || s['state']}"
          end.join("\n")
        end

        summary
      end
    end

    def format_comments(comments)
      return '_No comments yet_' if comments.empty?

      comments.map do |comment|
        author = comment['user']['login']
        body = comment['body']
        truncated_body = body.length > 150 ? body[0..150] + '...' : body
        created = format_date(comment['created_at'])

        "**@#{author}** (#{created}):\n#{truncated_body}"
      end.join("\n\n")
    end

    def context_file_path(repo, pr_number)
      owner, name = repo.split('/')
      File.join(CONTEXT_DIR, owner, name, "PR-#{pr_number}.md")
    end

    def save_context(file_path, content)
      FileUtils.mkdir_p(File.dirname(file_path))

      if File.exist?(file_path)
        existing_content = File.read(file_path)
        content = merge_with_existing_notes(content, existing_content)
      end

      File.write(file_path, content)
    end

    def merge_with_existing_notes(new_content, old_content)
      # Extract everything after the notes marker from old content
      if old_content.include?(NOTES_MARKER)
        old_notes = old_content.split(NOTES_MARKER, 2)[1]

        # Replace the notes section in new content with the old notes
        if new_content.include?(NOTES_MARKER)
          new_content.split(NOTES_MARKER, 2)[0] + NOTES_MARKER + old_notes
        else
          new_content
        end
      else
        new_content
      end
    end
  end
end
