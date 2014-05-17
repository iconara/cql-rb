# encoding: utf-8

require 'spec_helper'


module Cql
  module Client
    describe DataCenterAwareConnectionStrategy do
      describe '#connect?' do
        it 'it returns true when the peer is in one of the specified data centers' do
          strategy = described_class.new(%w[foo bar])
          connect = strategy.connect?({'data_center' => 'foo'})
          connect.should be_true
        end

        it 'it returns false when the peer is not in one of the specified data centers' do
          strategy = described_class.new(%w[foo bar])
          connect = strategy.connect?({'data_center' => 'baz'})
          connect.should be_false
        end
      end
    end
  end
end