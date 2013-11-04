# encoding: utf-8

module Cql
  module Client
    # @private
    class ConnectionManager
      include Enumerable

      def initialize(strategy=RandomConnectionSelectionStrategy.new)
        @strategy = strategy
        @connections = []
        @lock = Mutex.new
      end

      def add_connections(connections)
        @lock.synchronize do
          @connections += connections
          connections.each do |connection|
            connection.on_closed do
              @lock.synchronize do
                @connections = @connections.reject { |c| c == connection }
              end
            end
          end
        end
      end

      def connected?
        @connections.any?
      end

      def snapshot
        @lock.synchronize do
          @connections.dup
        end
      end

      def connection
        raise NotConnectedError unless connected?
        @strategy.select_connection(@connections)
      end

      def each_connection(&callback)
        return self unless block_given?
        raise NotConnectedError unless connected?
        @connections.each(&callback)
      end
      alias_method :each, :each_connection
    end
  end

  class RandomConnectionSelectionStrategy
    def select_connection(connections)
      connections.sample
    end
  end
end
