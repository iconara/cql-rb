module Cql
  class Client
    class Connection
      attr_accessor :connection_id, :host, :keyspace

      def initialize(connections, connection_id, host)
        @connections = connections
        @connection_id = connection_id
        @host = host
        @keyspace = nil
      end
    end
  end
end
