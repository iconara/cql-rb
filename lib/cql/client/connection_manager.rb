# encoding: utf-8

module Cql
  module Client
    # @private
    class ConnectionManager
      include Enumerable

      def initialize
        @connections = [].freeze
        @lock = Mutex.new
      end

      def add_connections(connections)
        @lock.synchronize do
          @connections = (@connections + connections).freeze
          connections.each do |connection|
            connection.on_closed do
              @lock.synchronize do
                @connections = (@connections - [connection]).freeze
              end
            end
          end
        end
      end

      def connected?
        !snapshot.empty?
      end

      def snapshot
        connections = nil
        @lock.lock
        begin
          connections = @connections
        ensure
          @lock.unlock
        end
        connections
      end

      def random_connection
        connections = snapshot
        raise NotConnectedError if connections.empty?
        connections.sample
      end

      def each_connection(&callback)
        return self unless block_given?
        connections = snapshot
        raise NotConnectedError if connections.empty?
        connections.each(&callback)
      end
      alias_method :each, :each_connection
    end
  end
end
