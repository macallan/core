require 'json'
require 'fileutils'
require 'time'

module Core
  class PRCache
    CACHE_DIR = File.expand_path('~/.core/cache')
    CACHE_FILE = File.join(CACHE_DIR, 'prs.json')

    SYMBOL_FIELDS = %i[ci_status review_status].freeze

    # Returns { prs_by_repo: Hash, cached_at: Time } or nil
    def self.read
      return nil unless File.exist?(CACHE_FILE)

      raw = JSON.parse(File.read(CACHE_FILE))
      cached_at = Time.parse(raw['cached_at'])

      prs_by_repo = {}
      raw['prs_by_repo'].each do |repo, prs|
        prs_by_repo[repo] = prs.map do |pr|
          symbolized = pr.transform_keys(&:to_sym)
          SYMBOL_FIELDS.each do |field|
            symbolized[field] = symbolized[field]&.to_sym
          end
          # Recalculate age fields from timestamps
          symbolized[:age] = calculate_age(symbolized[:created_at])
          symbolized[:updated_age] = calculate_age(symbolized[:updated_at])
          symbolized
        end
      end

      { prs_by_repo: prs_by_repo, cached_at: cached_at }
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    # Atomic write: write to .tmp then rename
    def self.write(prs_by_repo)
      FileUtils.mkdir_p(CACHE_DIR)

      serialized = {}
      prs_by_repo.each do |repo, prs|
        serialized[repo] = prs.map do |pr|
          pr.transform_keys(&:to_s).tap do |h|
            SYMBOL_FIELDS.each do |field|
              key = field.to_s
              h[key] = h[key].to_s if h[key]
            end
          end
        end
      end

      data = { 'cached_at' => Time.now.iso8601, 'prs_by_repo' => serialized }
      tmp = "#{CACHE_FILE}.tmp"
      File.write(tmp, JSON.pretty_generate(data))
      File.rename(tmp, CACHE_FILE)
    rescue Errno::ENOSPC, Errno::EACCES
      # Silently fail on disk full or permission errors
    end

    def self.exist?
      File.exist?(CACHE_FILE)
    end

    @bg_mutex = Mutex.new
    @bg_thread = nil

    # Spawn a single background thread to refresh the cache.
    # No-ops if one is already running. The block receives no args and
    # must return prs_by_repo. An optional +on_complete+ callback is
    # called with the fresh prs_by_repo after the cache is written.
    def self.refresh_in_background(on_complete: nil, &block)
      @bg_mutex.synchronize do
        return if @bg_thread&.alive?

        @bg_thread = Thread.new do
          prs_by_repo = block.call
          write(prs_by_repo)
          on_complete&.call(prs_by_repo)
        rescue => e
          $stderr.puts "[bg-refresh] #{e.class}: #{e.message}" if ENV['DEBUG']
        end
      end
      @bg_thread
    end

    # Duplicate of PRFetcher#calculate_age — pure function on timestamps
    def self.calculate_age(created_at)
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
