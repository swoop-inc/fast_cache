require 'spec_helper'

describe FastCache::Cache do

  context 'empty cache' do
    subject { described_class.new(5, 60, 1) }

    its(:empty?) { should be_true }
    its(:length) { should eq 0 }
    its(:size) { should eq 0 }
    its(:count) { should eq 0 }

    it 'returns nil' do
      subject[:foo].should be_nil
    end
  end

  context 'non-empty cache' do
    before do
      @cache = described_class.new(3, 60, 1)
      @cache[:a] = 1
      @cache[:b] = 2
      @cache[:c] = 3
    end
    subject { @cache }

    its(:empty?) { should be_false }
    its(:length) { should eq 3 }
    its(:size) { should eq 3 }
    its(:count) { should eq 3 }

    it 'returns stored values' do
      subject[:a].should eq 1
      subject[:b].should eq 2
      subject[:c].should eq 3
    end

    it 'replaces stored values' do
      subject[:a] = 10

      subject[:a].should eq 10
    end

    describe '#fetch' do
      it 'fetches from the cache when a key is present' do
        subject.fetch(:a) do
          'failure'.should eq 'fetch body should not be called'
        end.should eq 1
      end

      it 'evaluates and stores the value when it is absent' do
        subject.fetch(:d) do
          5
        end.should eq 5
        subject[:d].should eq 5
      end
    end

    describe '#delete' do
      it 'deletes entries' do
        subject.delete(:a).should eq 1
        subject.count.should eq 2
        subject.delete(:c).should eq 3
        subject.count.should eq 1
      end

      it 'returns nil for missing keys' do
        subject.delete(:d).should be_nil
        subject.count.should eq 3
      end
    end

    describe '#clear' do
      it 'clears the cache' do
        subject.clear

        subject.should be_empty
      end
    end

    describe '#each' do
      it 'yields key value pairs' do
        expect do |b|
          subject.each(&b)
        end.to yield_successive_args([:a, 1], [:b, 2], [:c, 3])
      end

      it 'returns an Enumerator when called without a block' do
        subject.each.should be_kind_of Enumerator
      end
    end

    describe '#inspect' do
      it do
        subject.inspect.should eq '<FastCache::Cache count=3 max_size=3 ttl=60.0>'
      end
    end

    describe 'LRU behaviors' do
      it 'removes least recently accessed entries when full' do
        subject[:d] = 4

        subject[:a].should be_nil
        subject[:b].should eq 2

        subject[:b] # access
        subject[:e] = 6

        subject[:b].should eq 2
        subject[:c].should be_nil
        subject[:d].should eq 4
        subject[:e].should eq 6
      end
    end
  end

  describe 'TTL behaviors' do
    context 'immediate expiration' do
      before do
        @cache = described_class.new(3, 0, 1)
        @cache[:a] = 1
      end
      subject { @cache }

      it 'reports the element count prior to expiration checking' do
        subject.count.should eq 1
      end

      it 'expires all entries' do
        subject.expire!

        subject.count.should eq 0
      end

      it 'removes all entries upon access' do
        subject[:a].should be_nil

        subject.fetch(:a) do
          true.should be_true
          5
        end.should == 5

        subject[:a].should be_nil
      end
    end

    context '1 min expiration' do
      before do
        @t = Time.now
        @cache = described_class.new(3, 60, 1)
        @cache[:a] = 1
      end
      subject { @cache }

      it 'removes expired values upon access' do
        Timecop.freeze(@t + 61) do
          subject[:a].should be_nil
        end
      end

      it 'removes expired values when other values are written' do
        Timecop.freeze(@t + 61) do
          subject.count.should eq 1

          subject[:b] = 2

          subject.count.should eq 1
          subject[:a].should be_nil
          subject[:b].should eq 2
        end
      end

      it 'removes expired values when other values are accessed' do
        Timecop.freeze(@t + 30) do
          subject[:b] = 2
        end

        Timecop.freeze(@t + 61) do
          subject.count.should eq 2

          subject[:b] # access

          subject.count.should eq 1
          subject[:a].should be_nil
          subject[:b].should eq 2
        end
      end

      it 'expires entries' do
        Timecop.freeze(@t + 30) do
          subject[:b] = 2
        end

        Timecop.freeze(@t + 61) do
          subject.expire!

          subject.count.should eq 1
          subject[:b].should eq 2
        end
      end
    end

    context 'delayed expiration check' do
      before do
        @t = Time.now
        @cache = described_class.new(3, 60, 10)
        @cache[:a] = 1 # 1 op
        @cache[:b] = 2 # 2 ops
      end
      subject { @cache }

      it 'removes expired values after a specified number of operations' do
        Timecop.freeze(@t + 61) do
          subject.count.should eq 2
          7.times do # 3..9 ops
            subject[:a].should eq nil
            subject.count.should == 1
          end
          # 10 ops
          subject[:a].should eq nil
          subject.count.should eq 0
        end
      end
    end
  end

end
