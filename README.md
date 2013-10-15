# FastCache &nbsp; [![Build Status](https://secure.travis-ci.org/swoop-inc/fast_cache.png)](http://travis-ci.org/swoop-inc/fast_cache?branch=master) [![Dependency Status](https://gemnasium.com/swoop-inc/fast_cache.png)](https://gemnasium.com/swoop-inc/fast_cache)


There are two reasons why you may want to skip this:

1. This is yet another caching gem, which is grounds for extreme suspicion.
2. Many Ruby developers don't care about performance.

If you're still reading, there are three reasons why this is worth checking out:

1. Performance is a feature users love. Products from 37signals' to Google's have proven this time and time again. Performance almost never matters if you are not successful but almost always does if you are. At [Swoop](http://swoop.com) we have tens of millions of users. We care about correctness, simplicity and maintainability but also about performance.

2. This cache benchmarks 10-100x faster than [ActiveSupport::Cache::MemoryStore](http://api.rubyonrails.org/classes/ActiveSupport/Cache/MemoryStore.html) without breaking a sweat. You can switch to FastCache in a couple minutes and, most likely, you won't have to refactor your tests. FastCache has 100% test coverage at 20+ hits/line. There are no third party runtime dependencies so you can use this anywhere with Ruby 1.9+.

3. The implementation exploits some neat features of Ruby's native data structures that could be useful and fun to learn about.


## Installation

Add this line to your application's Gemfile:

    gem 'fast_cache'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install fast_cache


## Usage

FastCache::Cache is an in-process cache with least recently used (LRU) and time to live (TTL) expiration semantics, which makes it an easy replacement for ActiveSupport::Cache::MemoryStore as well as a great candidate for the in-process portion of a hierarchical caching system (FastCache sitting in front of, say, memcached or Redis).

The current implementation is not thread-safe because at [Swoop](http://swoop.com) we prefer to handle simple concurrency in MRI Ruby via the [reactor pattern](http://en.wikipedia.org/wiki/Reactor_pattern) with [eventmachine](https://github.com/eventmachine/eventmachine). An easy way to add thread safety would be via a [synchronizing subclass](https://github.com/SamSaffron/lru_redux/blob/master/lib/lru_redux/thread_safe_cache.rb) or decorator.

The implementation does not use a separate thread for expiring stale cached values. Instead, before a value is returned from the cache, its expiration time is checked. In order to avoid the case where a value that is never accessed cannot be removed, every _N_ operations the cache removes all expired values.

```ruby
require 'fast_cache'

# Creates a cache of one million items at most an hour old
cache = FastCache::Cache.new(1_000_000, 60*60)

# Sames as above but removes expired items after every 10,000 operations.
# The default is after 100 operations.
cache = FastCache::Cache.new(1_000_000, 60*60, 10_000)

# Cache the result of an expensive operation
cached_value = cache.fetch('my_key') do
  HardProblem.new(inputs).solve.result
end

# Proactively release as much memory as you can
cache.expire!
```


## Performance

If you are looking for an in-process cache with LRU and time-to-live expiration semantics the go-to implementation is [ActiveSupport::Cache::MemoryStore](http://api.rubyonrails.org/classes/ActiveSupport/Cache/MemoryStore.html), which as of Rails 3.1 [started marshaling](http://apidock.com/rails/v3.2.13/ActiveSupport/Cache/Entry/value) the data even though the keys and values never leave the process boundary. The performance of the cache is dominated by marshaling and loading, i.e., by the size and complexity of keys and values. The better job you do of finding large, complex, cacheable data structures, the slower it will run. That doesn't feel right for an in-process cache.

We benchmark against [LruRedux::Cache](https://github.com/SamSaffron/lru_redux), which was the inspiration behind FastCache::Cache and, of course, ActiveSupport::Cache::MemoryStore.

```bash
gem install lru_redux
gem install activesupport
bin/fast-cache-benchmark
```

The [benchmark](bin/fast-cache-benchmark) includes a simple value test (caching just the Symbol `:value`) and a more complex value test (caching a [medium-size data structure](bench/caching_sample.json)). Both tests run for one million iterations with an expected cache hit rate of 50%.

```
$ bin/fast-cache-benchmark
Simple value benchmark
Rehearsal ------------------------------------------------
lru_redux      2.200000   0.020000   2.220000 (  2.213863)
fast_cache    10.840000   0.040000  10.880000 ( 10.879686)
memory_store  53.300000   0.150000  53.450000 ( 53.459458)
-------------------------------------- total: 66.550000sec

                   user     system      total        real
lru_redux      4.140000   0.010000   4.150000 (  4.153546)
fast_cache    14.140000   0.040000  14.180000 ( 14.177038)
memory_store  71.510000   0.140000  71.650000 ( 71.659656)

Complex value benchmark
Rehearsal ------------------------------------------------
lru_redux      6.150000   0.030000   6.180000 (  6.180459)
fast_cache    17.020000   0.040000  17.060000 ( 17.058475)
memory_store 1053.360000   1.620000 1054.980000 (1055.275237)
------------------------------------ total: 1078.220000sec

                   user     system      total        real
lru_redux      7.830000   0.020000   7.850000 (  7.854760)
fast_cache    19.620000   0.030000  19.650000 ( 19.650379)
memory_store 1286.790000   1.850000 1288.640000 (1289.115472)
```

In both tests FastCache::Cache is 2-3x slower than LruRedux::Cache, which only provides LRU expiration semantics. For small values, FastCache::Cache is 5x faster than ActiveSupport::Cache::MemoryStore. For more complex values the difference grows to 50-100x (67x in the particular benchmark).

In one case of CSV generation where every row involved looking up model attributes FastCache was more than 100 times faster. Operations that took many minutes now happen in seconds.


## Implementation

[Sam Saffron](https://github.com/SamSaffron) noticed that Ruby 1.9 Hash's property to preserve insertion order can be used as a second index into the hash, in addition to indexing by a key.  That led Sam to create the [lru_redux](https://github.com/SamSaffron/lru_redux) gem, whose cache behaves in a very non-intuitive way at first glance. For example, the simplified pseudocode for the cache get operation is:

```
cache[key]:
  value = @data.delete(key)
  @data[key] = value
  value
```

In other words, the code performs two mutating operations (delete and insert) in order to satisfy a single non-mutating operation (get). Why? The reason is that this is how the cache maintains its least recently used removal property. The picture below shows the get operation step-by-step using a fictitious cache of names against some difficult-to-compute scores.

![lru](https://www.lucidchart.com/publicSegments/view/525be92f-6034-40f7-b3b6-377d0a005604/image.png)
If the cache gets full, it can create space by removing elements from the front of its insertion order data structure using [Hash#shift](http://www.ruby-doc.org/core-2.0.0/Hash.html#method-i-shift).

For those of you familiar with [Redis](http://redis.io), this approach to using a Ruby Hash may remind you of [sorted sets](http://redis.io/commands#sorted_set).

To add time-based expiration, we need to:

1. Keep track of expiration times.
2. Index by expiration time, to clean up in `expire!`.
3. Efficiently remove items from the expiration index when a stale item is detected.

By exploiting the dual index property of Hash we can achieve this with just one extra "expires" hash, which is the inverse of our "data" hash. We keep the data hash ordered by recency of use and the expires hash ordered by insertion order, which is also the removal order because the time to live is constant. The diagram below shows the object relationships.

![lru-and-ttl](https://www.lucidchart.com/publicSegments/view/525c994d-5b2c-48d3-aaf6-3fcb0a00d3e5/image.png)


## Contributing

1. Fork the repo
2. Create a topic branch (`git checkout -b my-new-feature`)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create new Pull Request

Please don't change the version and add solid tests: [simplecov](https://github.com/colszowka/simplecov) is set to 100% minimum coverage.


## Credits

[Sam Saffron](https://github.com/SamSaffron) for his guiding insight as well as [Richard Schneeman](https://github.com/schneems) and [Piotr Sarnacki](https://github.com/drogus) for [helping improve](https://github.com/rails/rails/issues/11512) ActiveSupport::Cache::MemoryStore.

Who says Ruby can't be fun **and** fast?

![swoop](http://blog.swoop.com/Portals/160747/images/logo1.png)

fast_cache was written by [Simeon Simeonov](https://github.com/ssimeonov) and is maintained and funded by [Swoop, Inc,](http://swoop.com).

License
-------

fast_cache is Copyright © 2013 Simeon Simeonov and Swoop, Inc. It is free software, and may be redistributed under the terms specified below.

MIT License

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
