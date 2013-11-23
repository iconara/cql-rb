# encoding: ascii-8bit

require 'spec_helper'


module Cql
  module Protocol
    describe QueryRequest do
      describe '#initialize' do
        it 'raises an error when the CQL is nil' do
          expect { QueryRequest.new(nil, :one) }.to raise_error(ArgumentError)
        end

        it 'raises an error when the consistency is nil' do
          expect { QueryRequest.new('USE system', nil) }.to raise_error(ArgumentError)
        end

        it 'raises an error when the consistency is invalid' do
          expect { QueryRequest.new('USE system', :hello) }.to raise_error(ArgumentError)
        end
      end

      describe '#encode_frame' do
        it 'encodes a QUERY request frame' do
          bytes = QueryRequest.new('USE system', :all).encode_frame(3)
          bytes.should == "\x01\x00\x03\x07\x00\x00\x00\x10\x00\x00\x00\x0aUSE system\x00\x05"
        end

        it 'encodes a QUERY request frame with tracing' do
          bytes = QueryRequest.new('USE system', :all, true).encode_frame(3)
          bytes.should == "\x01\x02\x03\x07\x00\x00\x00\x10\x00\x00\x00\x0aUSE system\x00\x05"
        end

        it 'correctly encodes queries with multibyte characters' do
          bytes = QueryRequest.new("INSERT INTO users (user_id, first, last, age) VALUES ('test', 'ümlaut', 'test', 1)", :all).encode_frame(3)
          bytes.should eql_bytes("\x01\x00\x03\a\x00\x00\x00Y\x00\x00\x00SINSERT INTO users (user_id, first, last, age) VALUES ('test', '\xC3\xBCmlaut', 'test', 1)\x00\x05")
        end
      end

      describe '#to_s' do
        it 'returns a pretty string' do
          request = QueryRequest.new('SELECT * FROM system.peers', :local_quorum)
          request.to_s.should == 'QUERY "SELECT * FROM system.peers" LOCAL_QUORUM'
        end
      end

      describe '#eql?' do
        it 'returns true when the CQL and consistency are the same' do
          q1 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q2 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q2.should eql(q2)
        end

        it 'returns false when the consistency is different' do
          q1 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q2 = QueryRequest.new('SELECT * FROM system.peers', :three)
          q1.should_not eql(q2)
        end

        it 'returns false when the CQL is different' do
          q1 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q2 = QueryRequest.new('SELECT * FROM peers', :two)
          q1.should_not eql(q2)
        end

        it 'does not know about CQL syntax' do
          q1 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q2 = QueryRequest.new('SELECT   *   FROM   system.peers', :two)
          q1.should_not eql(q2)
        end

        it 'is aliased as ==' do
          q1 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q2 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q1.should == q2
        end
      end

      describe '#hash' do
        it 'has the same hash code as another identical object' do
          q1 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q2 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q1.hash.should == q2.hash
        end

        it 'does not have the same hash code when the consistency is different' do
          q1 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q2 = QueryRequest.new('SELECT * FROM system.peers', :three)
          q1.hash.should_not == q2.hash
        end

        it 'does not have the same hash code when the CQL is different' do
          q1 = QueryRequest.new('SELECT * FROM system.peers', :two)
          q2 = QueryRequest.new('SELECT * FROM peers', :two)
          q1.hash.should_not == q2.hash
        end
      end
    end
  end
end