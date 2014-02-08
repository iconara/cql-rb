# encoding: utf-8

require 'spec_helper'


module Cql
  module Client
    describe SynchronousPreparedStatement do
      let :statement do
        described_class.new(async_statement)
      end

      let :async_statement do
        double(:async_statement, metadata: metadata, result_metadata: result_metadata)
      end

      let :metadata do
        double(:metadata)
      end

      let :result_metadata do
        double(:result_metadata)
      end

      let :promise do
        Promise.new
      end

      let :future do
        promise.future
      end

      describe '#metadata' do
        it 'returns the async statement\'s metadata' do
          statement.metadata.should equal(async_statement.metadata)
        end
      end

      describe '#result_metadata' do
        it 'returns the async statement\'s result metadata' do
          statement.result_metadata.should equal(async_statement.result_metadata)
        end
      end

      describe '#execute' do
        it 'it calls #execute on the async statement and waits for the result' do
          result = double(:result)
          async_statement.should_receive(:execute).with('one', 'two', :three).and_return(future)
          promise.fulfill(result)
          statement.execute('one', 'two', :three).should equal(result)
        end
      end

      describe '#batch' do
        let :batch do
          double(:batch)
        end

        context 'when called without a block' do
          it 'delegates to the asynchronous statement and wraps the returned object in a synchronous wrapper' do
            async_statement.stub(:batch).with(:unlogged, trace: true).and_return(batch)
            batch.stub(:execute).and_return(Cql::Future.resolved(VoidResult.new))
            b = statement.batch(:unlogged, trace: true)
            b.execute.should be_a(VoidResult)
          end
        end

        context 'when called with a block' do
          it 'delegates to the asynchronous statement' do
            async_statement.stub(:batch).with(:counter, trace: true).and_yield(batch).and_return(Cql::Future.resolved(VoidResult.new))
            yielded_batch = nil
            statement.batch(:counter, trace: true) { |b| yielded_batch = b }
            yielded_batch.should equal(batch)
          end

          it 'waits for the operation to complete' do
            async_statement.stub(:batch).with(:counter, anything).and_yield(batch).and_return(Cql::Future.resolved(VoidResult.new))
            result = statement.batch(:counter) { |b| }
            result.should be_a(VoidResult)
          end
        end
      end

      describe '#add_to_batch' do
        it 'delegates to the async statement' do
          batch = double(:batch)
          connection = double(:connection)
          bound_arguments = [1, 2, 3]
          async_statement.stub(:add_to_batch)
          statement.add_to_batch(batch, connection, bound_arguments)
          async_statement.should have_received(:add_to_batch).with(batch, connection, bound_arguments)
        end
      end

      describe '#pipeline' do
        it 'executes the statement multiple times and waits for all the results' do
          result1 = double(:result1)
          result2 = double(:result2)
          async_statement.stub(:execute).with('one', 'two', :three).and_return(Future.resolved(result1))
          async_statement.stub(:execute).with('four', 'file', :all).and_return(Future.resolved(result2))
          results = statement.pipeline do |p|
            p.execute('one', 'two', :three)
            p.execute('four', 'file', :all)
          end
          results.should eql([result1, result2])
        end

        it 'does nothing when statements are executed' do
          statement.pipeline { |p| }.should == []
        end
      end

      describe '#async' do
        it 'returns an asynchronous statement' do
          statement.async.should equal(async_statement)
        end
      end

      context 'when exceptions are raised' do
        it 'replaces the backtrace of the asynchronous call to make it less confusing' do
          error = CqlError.new('Bork')
          error.set_backtrace(['Hello', 'World'])
          future.stub(:value).and_raise(error)
          async_statement.stub(:execute).and_return(future)
          begin
            statement.execute('SELECT * FROM something')
          rescue CqlError => e
            e.backtrace.first.should match(%r{/synchronous_prepared_statement.rb:\d+:in `execute'})
          end
        end

        it 'does not replace the backtrace of non-CqlError errors' do
          future.stub(:value).and_raise('Bork')
          async_statement.stub(:execute).and_return(future)
          begin
            statement.execute('SELECT * FROM something')
          rescue => e
            e.backtrace.first.should_not match(%r{/synchronous_prepared_statement.rb:\d+:in `execute'})
          end
        end
      end
    end
  end
end