require 'yaml'
require 'fileutils'

module Core
  class Config
    CONFIG_PATH = File.expand_path('~/.core.yml')

    def self.load
      if File.exist?(CONFIG_PATH)
        YAML.load_file(CONFIG_PATH) || default_config
      else
        default_config
      end
    rescue => e
      warn "Error loading config: #{e.message}"
      default_config
    end

    def self.save(data)
      FileUtils.mkdir_p(File.dirname(CONFIG_PATH))
      File.write(CONFIG_PATH, YAML.dump(data))
    end

    def self.update_last_checked(repo, timestamp)
      config = load
      config['last_checked'] ||= {}
      config['last_checked'][repo] = timestamp.iso8601
      save(config)
    end

    def self.get_last_checked(repo)
      config = load
      last_checked = config.dig('last_checked', repo)
      last_checked ? Time.parse(last_checked) : nil
    rescue
      nil
    end

    def self.default_config
      {
        'repos' => [],
        'authors' => [],
        'last_checked' => {},
        'tmux' => {
          'default' => {
            'panes' => 2,
            'split' => 'horizontal'
          },
          'repos' => {}
        }
      }
    end

    def self.repos
      load['repos'] || []
    end

    def self.add_repo(repo)
      config = load
      config['repos'] ||= []
      config['repos'] << repo unless config['repos'].include?(repo)
      save(config)
    end

    def self.remove_repo(repo)
      config = load
      config['repos'] ||= []
      removed = config['repos'].delete(repo)
      if removed && config['last_checked']
        config['last_checked'].delete(repo)
      end
      save(config)
      removed
    end

    def self.authors
      load['authors'] || []
    end

    def self.add_author(username)
      config = load
      config['authors'] ||= []
      config['authors'] << username unless config['authors'].include?(username)
      save(config)
    end

    def self.remove_author(username)
      config = load
      config['authors'] ||= []
      removed = config['authors'].delete(username)
      save(config)
      removed
    end

    def self.tmux_config(repo = nil)
      config = load
      tmux_config = config['tmux'] || default_config['tmux']

      # If a specific repo is requested and has custom config, return that
      if repo && tmux_config['repos'] && tmux_config['repos'][repo]
        tmux_config['repos'][repo]
      else
        # Otherwise return the default tmux config
        tmux_config['default'] || default_config['tmux']['default']
      end
    end
  end
end
