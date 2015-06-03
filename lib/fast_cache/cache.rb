module FastCache

  # @author {https://github.com/ssimeonov Simeon Simeonov}, {http://swoop.com Swoop, Inc.}
  #
  # In-process cache with least-recently used (LRU) and time-to-live (TTL)
  # expiration semantics.
  #
  # This implementation is not thread-safe. It does not use a thread to clean
  # up expired values. Instead, an expiration check is performed:
  #
  # 1. Every time you retrieve a value, against that value. If the value has
  #    expired, it will be removed and `nil` will be returned.
  #
  # 2. Every `expire_interval` operations as the cache is used to remove all
  #    expired values up to that point.
  #
  # For manual expiration call {#expire!}.
  #
  # @example
  #
  #   # Create cache with one million elements no older than 1 hour
  #   cache = FastCache::Cache.new(1_000_000, 60 * 60)
  #   cached_value = cache.fetch('cached_value_key') do
  #     # Expensive computation that returns the value goes here
  #   end
  class Cache

    # Initializes the cache.
    #
    # @param [Integer] max_size Maximum number of elements in the cache.
    # @param [Numeric] ttl Maximum time, in seconds, for a value to stay in
    #                      the cache.
    # @param [Integer] expire_interval Number of cache operations between
    #                                  calls to {#expire!}.
    def initialize(max_size, ttl, expire_interval = 100)
      @max_size = max_size
      @ttl = ttl.to_f
      @expire_interval = expire_interval
      @op_count = 0
      @data = {}
      @expires_at = {}
      @cleanup = Proc.new if block_given?
    end

    # Retrieves a value from the cache, if available and not expired, or
    # yields to a block that calculates the value to be stored in the cache.
    #
    # @param key [Object] the key to look up or store at
    # @return [Object] the value at the key
    # @yield yields when the value is not present
    # @yieldreturn [Object] the value to store in the cache.
    def fetch(key)
      found, value = get(key)
      if found
        value
      else
        store(key, yield)
      end
    end

    # Retrieves a value from the cache.
    #
    # @param key [Object] the key to look up
    # @return [Object, nil] the value at the key, when present, or `nil`
    def [](key)
      _, value = get(key)
      value
    end

    # Stores a value in the cache.
    #
    # @param key [Object] the key to store at
    # @param val [Object] the value to store
    # @return [Object] the value
    def []=(key, val)
      expire!
      store(key, val)
    end

    # Removes a value from the cache.
    #
    # @param key [Object] the key to remove at
    # @return [Object, nil] the value at the key, when present, or `nil`
    def delete(key)
      entry = @data.delete(key)
      if entry
        @expires_at.delete(entry)
        @cleanup.call(entry.value) if @cleanup
        entry.value
      else
        nil
      end
    end

    # Checks whether the cache is empty.
    #
    # @note calls to {#empty?} do not count against `expire_interval`.
    #
    # @return [Boolean]
    def empty?
      count == 0
    end

    # Clears the cache.
    #
    # @return [self]
    def clear
      @data.values.map(&:value).map(&@cleanup) if @cleanup
      @data.clear
      @expires_at.clear
      self
    end

    # Returns the number of elements in the cache.
    #
    # @note calls to {#empty?} do not count against `expire_interval`.
    #       Therefore, the number of elements is that prior to any expiration.
    #
    # @return [Integer] number of elements in the cache.
    def count
      @data.count
    end

    alias_method :size, :count
    alias_method :length, :count

    # Allows iteration over the items in the cache.
    #
    # Enumeration is stable: it is not affected by changes to the cache,
    # including value expiration. Expired values are removed first.
    #
    # @note The returned values could have expired by the time the client
    #       code gets to accessing them.
    # @note Because of its stability, this operation is very expensive.
    #       Use with caution.
    #
    # @return [Enumerator, Array<key, value>] an Enumerator, when a block is
    #     not provided, or an array of key/value pairs.
    # @yield [Array<key, value>] key/value pairs, when a block is provided.
    def each(&block)
      expire!
      @data.map { |key, entry| [key, entry.value] }.each(&block)
    end

    # Removes expired values from the cache.
    #
    # @return [self]
    def expire!
      check_expired(Time.now.to_f)
      self
    end

    # Returns information about the number of objects in the cache, its
    # maximum size and TTL.
    #
    # @return [String]
    def inspect
      "<#{self.class.name} count=#{count} max_size=#{@max_size} ttl=#{@ttl}>"
    end

    private

    # @private
    class Entry
      attr_reader :value
      attr_reader :expires_at

      def initialize(value, expires_at)
        @value = value
        @expires_at = expires_at
      end
    end

    def get(key)
      t = Time.now.to_f
      check_expired(t)
      found = true
      entry = @data.delete(key) { found = false }
      if found
        if entry.expires_at <= t
          @expires_at.delete(entry)
          @cleanup.call(entry.value) if @cleanup
          return false, nil
        else
          @data[key] = entry
          return true, entry.value
        end
      else
        return false, nil
      end
    end

    def store(key, val)
      expires_at = Time.now.to_f + @ttl
      entry = Entry.new(val, expires_at)
      store_entry(key, entry)
      val
    end

    def store_entry(key, entry)
      found = true
      old_entry = @data.delete(key) { found = false }
      @cleanup.call(old_entry.value) if @cleanup && found
      @data[key] = entry
      @expires_at[entry] = key
      shrink_if_needed
    end

    def shrink_if_needed
      if @data.length > @max_size
        entry = delete(@data.shift)
        @expires_at.delete(entry)
        @cleanup.call(entry.value) if @cleanup
      end
    end

    def check_expired(t)
      if (@op_count += 1) % @expire_interval == 0
        while (key_value_pair = @expires_at.first) &&
            (entry = key_value_pair.first).expires_at <= t
          key = @expires_at.delete(entry)
          entry = @data.delete(key)
          @cleanup.call(entry.value) if @cleanup
        end
      end
    end
  end

end
