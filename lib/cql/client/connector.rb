# encoding: utf-8

module Cql
  module Client
    # @private
    class ClusterConnector
      def initialize(sequence, logger)
        @sequence = sequence
        @logger = logger
      end

      def connect_all(hosts, connections_per_node)
        connections = hosts.flat_map do |host|
          Array.new(connections_per_node) do
            f = @sequence.connect(host)
            f.on_value { |connection| register_logging(connection) }
            f.recover do |error|
              @logger.warn('Failed connecting to node at %s: %s' % [host, error.message])
              FailedConnection.new(error, host)
            end
          end
        end
        Future.all(*connections).map do |connections|
          connected_connections = connections.select(&:connected?)
          if connected_connections.empty?
            e = connections.first.error
            if e.is_a?(Cql::QueryError) && e.code == 0x100
              e = AuthenticationError.new(e.message)
            end
            raise e
          end
          connected_connections
        end
      end

      private

      def register_logging(connection)
        args = [connection[:host_id], connection.host, connection.port, connection[:data_center]]
        @logger.info('Connected to node %s at %s:%d in data center %s' % args)
        connection.on_closed do |cause|
          message = 'Connection to node %s at %s:%d in data center %s closed' % args
          if cause
            message << (' unexpectedly: %s' % cause.message)
            @logger.warn(message)
          else
            @logger.info(message)
          end
        end
      end
    end

    # @private
    class Connector
      def initialize(steps)
        @steps = steps.dup
      end

      def connect(host)
        pending_connection = PendingConnection.new(host)
        seed = Future.resolved(pending_connection)
        f = @steps.reduce(seed) do |chain, step|
          chain.flat_map do |pending_connection|
            step.run(pending_connection)
          end
        end
        f.map do |pending_connection|
          pending_connection.connection
        end
      end
    end

    # @private
    class ConnectStep
      def initialize(io_reactor, port, connection_timeout, logger)
        @io_reactor = io_reactor
        @port = port
        @connection_timeout = connection_timeout
        @logger = logger
      end

      def run(pending_connection)
        @logger.debug('Connecting to node at %s:%d' % [pending_connection.host, @port])
        @io_reactor.connect(pending_connection.host, @port, @connection_timeout).map do |connection|
          pending_connection.with_connection(connection)
        end
      end
    end

    # @private
    class CacheOptionsStep
      def run(pending_connection)
        f = pending_connection.execute(Protocol::OptionsRequest.new)
        f.on_value do |supported_options|
          pending_connection[:cql_version] = supported_options['CQL_VERSION']
          pending_connection[:compression] = supported_options['COMPRESSION']
        end
        f.map(pending_connection)
      end
    end

    # @private
    class InitializeStep
      def initialize(compressor, logger)
        @compressor = compressor
        @logger = logger
      end

      def run(pending_connection)
        compression = @compressor && @compressor.algorithm
        supported_algorithms = pending_connection[:compression]
        if @compressor && !supported_algorithms.include?(@compressor.algorithm)
          @logger.warn(%[Compression algorithm "#{@compressor.algorithm}" not supported (server supports "#{supported_algorithms.join('", "')}")])
          compression = nil
        elsif @compressor
          @logger.debug('Using "%s" compression' % @compressor.algorithm)
        end
        f = pending_connection.execute(Protocol::StartupRequest.new(nil, compression))
        f.map do |startup_response|
          if startup_response.is_a?(AuthenticationRequired)
            pending_connection.with_authentication_class(startup_response.authentication_class)
          else
            pending_connection
          end
        end
      end
    end

    # @private
    class AuthenticationStep
      def initialize(authenticator, protocol_version)
        @authenticator = authenticator
        @protocol_version = protocol_version
      end

      def run(pending_connection)
        if pending_connection.authentication_class
          if @authenticator && @authenticator.supports?(pending_connection.authentication_class, @protocol_version)
            auth_request = @authenticator.initial_request(@protocol_version)
            f = pending_connection.execute(auth_request)
            f.map(pending_connection)
          elsif @authenticator
            Future.failed(AuthenticationError.new('Authenticator does not support the required authentication class "%s" and/or protocol version %d' % [pending_connection.authentication_class, @protocol_version]))
          else
            Future.failed(AuthenticationError.new('Server requested authentication, but no authenticator provided'))
          end
        else
          Future.resolved(pending_connection)
        end
      end
    end

    # @private
    class CachePropertiesStep
      def run(pending_connection)
        request = Protocol::QueryRequest.new('SELECT data_center, host_id FROM system.local', nil, nil, :one)
        f = pending_connection.execute(request)
        f.on_value do |result|
          unless result.empty?
            pending_connection[:host_id] = result.first['host_id']
            pending_connection[:data_center] = result.first['data_center']
          end
        end
        f.map(pending_connection)
      end
    end

    # @private
    class PendingConnection
      attr_reader :host, :connection, :authentication_class

      def initialize(host, connection=nil, authentication_class=nil)
        @host = host
        @connection = connection
        @authentication_class = authentication_class
        @request_runner = RequestRunner.new
      end

      def with_connection(connection)
        self.class.new(host, connection, @authentication_class)
      end

      def with_authentication_class(authentication_class)
        self.class.new(host, @connection, authentication_class)
      end

      def [](key)
        @connection[key]
      end

      def []=(key, value)
        @connection[key] = value
      end

      def execute(request)
        @request_runner.execute(@connection, request)
      end
    end

    # @private
    class FailedConnection
      attr_reader :error, :host

      def initialize(error, host)
        @error = error
        @host = host
      end

      def connected?
        false
      end
    end
  end
end
