module Berkshelf::API
  # @note
  #   DependencyCache stores its data internally as a Mash
  #   The structure is as follows
  #
  #   {
  #     "cookbook_name" => {
  #       "x.y.z" => {
  #         :dependencies => { "cookbook_name" => "constraint" },
  #         :platforms => { "platform" => "constraint" }
  #       }
  #     }
  #   }
  class DependencyCache
    class << self
      # Read an archived cache and re-instantiate it
      #
      # @param [#to_s] filepath
      #   path to an archived cache
      #
      # @raise [Berkshelf::API::SaveNotFoundError]
      # @raise [Berkshelf::API::InvalidSaveError]
      #
      # @return [DependencyCache]
      def from_file(filepath)
        contents = JSON.parse(File.read(filepath.to_s))
        new(contents)
      rescue Errno::ENOENT => ex
        raise SaveNotFoundError.new(ex)
      rescue JSON::ParserError => ex
        raise InvalidSaveError.new(ex)
      end
    end

    include Berkshelf::API::Logging
    extend Forwardable
    def_delegators :@cache, :[], :[]=

    # @param [Hash] contents
    def initialize(contents = {})
      @warmed = false
      @cache  = Hash[contents]
    end

    # @param [RemoteCookbook] cookbook
    # @param [Ridley::Chef::Cookbook::Metadata] metadata
    #
    # @return [Hash]
    def add(cookbook, metadata)
      platforms    = metadata.platforms || Hash.new
      dependencies = metadata.dependencies || Hash.new
      @cache[cookbook.name.to_s] ||= Hash.new
      @cache[cookbook.name.to_s][cookbook.version.to_s] = {
        platforms: platforms,
        dependencies: dependencies,
        location_type: cookbook.location_type,
        location_path: cookbook.location_path
      }
    end

    # Clear any items added to this instance
    #
    # @return [Hash]
    def clear
      @cache.clear
    end

    # Check if the cache knows about the given cookbook version
    #
    # @param [#to_s] name
    # @param [#to_s] version
    #
    # @return [Boolean]
    def has_cookbook?(name, version)
      unless cookbook = @cache[name.to_s]
        return false
      end

      cookbook.has_key?(version.to_s)
    end

    # @param [String] name
    # @param [String] version
    #
    # @return [Hash]
    def remove(name, version)
      @cache[name.to_s].delete(version.to_s)
      if @cache[name.to_s].empty?
        @cache.delete(name.to_s)
      end
      @cache
    end

    # @return [Boolean]
    def empty?
      @cache.empty?
    end

    # @return [Hash]
    def to_hash
      @cache.to_hash
    end

    # @param [Hash] options
    #
    # @return [String]
    def to_json(options = {})
      JSON.generate(to_hash, options)
    end

    # @return [Array<RemoteCookbook>]
    def cookbooks
      [].tap do |remote_cookbooks|
        @cache.each_pair do |name, versions|
          versions.each do |version, metadata|
            remote_cookbooks << RemoteCookbook.new(name, version, metadata[:location_type], metadata[:location_path])
          end
        end
      end
    end

    def save(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, 'w+') { |f| f.write(self.to_json) }
    end

    def warmed?
      @warmed
    end

    def set_warmed
      @warmed = true
    end
  end
end
