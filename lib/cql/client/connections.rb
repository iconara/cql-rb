module Cql
  class Client
    class Connections < Hash
      attr_reader :client

      def initialize(client)
        @client = client
        @lock = Mutex.new
      end

      def add(future, host)
        future.on_complete do |connection_id|
          self[connection_id] = Connection.new(self, connection_id, host)
        end
      end

      def on_connection_close(connection, error)
        state = delete(connection.connection_id)
        return unless state
        # todo: don't retry on certain errors
        @client.connect_to_host(state.host)
      end

      def on_keyspace_change(keyspace, connection_id)
        connection = self[connection_id]
        return unless connection
        @lock.synchronize do
          connection.keyspace = keyspace
          return unless keyspace
        end
        @client.use(keyspace)
      end

      def keyspace
        @lock.synchronize do
          values.first.keyspace
        end
      end

      def needing_keyspace_update(keyspace)
        connections = @lock.synchronize do
          select { |_, connection| connection.keyspace != keyspace }
        end
        connections.map { |id, _| id }
      end
    end
  end
end

require 'cql/client/connection'
