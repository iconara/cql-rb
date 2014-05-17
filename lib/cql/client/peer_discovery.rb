# encoding: utf-8

module Cql
  module Client
    # @private
    class PeerDiscovery
      def initialize(seed_connections, connection_strategy)
        @seed_connections = seed_connections
        @connection_strategy = connection_strategy
        @request_runner = RequestRunner.new
      end

      def new_hosts
        connection = @seed_connections.sample
        request = Protocol::QueryRequest.new('SELECT peer, data_center, host_id, rpc_address FROM system.peers', nil, nil, :one)
        response = @request_runner.execute(connection, request)
        response.map do |result|
          result.each_with_object([]) do |peer_info, new_peers|
            host_id = peer_info['host_id']
            if @seed_connections.none? { |c| c[:host_id] == host_id } && @connection_strategy.connect?(peer_info)
              rpc_address = peer_info['rpc_address'].to_s
              rpc_address = peer_info['peer'].to_s if rpc_address == '0.0.0.0'
              new_peers << rpc_address
            end
          end
        end
      end
    end
  end
end
