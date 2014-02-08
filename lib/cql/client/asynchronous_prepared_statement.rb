# encoding: utf-8

module Cql
  module Client
    # @private
    class AsynchronousPreparedStatement < PreparedStatement
      # @private
      def initialize(cql, execute_options_decoder, connection_manager, logger)
        @cql = cql
        @execute_options_decoder = execute_options_decoder
        @connection_manager = connection_manager
        @logger = logger
        @request_runner = RequestRunner.new
      end

      def self.prepare(cql, execute_options_decoder, connection_manager, logger)
        statement = new(cql, execute_options_decoder, connection_manager, logger)
        futures = connection_manager.map do |connection|
          statement.prepare(connection)
        end
        Future.all(*futures).map(statement)
      rescue => e
        Future.failed(e)
      end

      def execute(*args)
        connection = @connection_manager.random_connection
        if connection[self]
          run(args, connection)
        else
          prepare(connection).flat_map do
            run(args, connection)
          end
        end
      rescue => e
        Future.failed(e)
      end

      def batch(type=:logged, options=nil)
        if type.is_a?(Hash)
          options = type
          type = :logged
        end
        b = AsynchronousBatch.new(type, @execute_options_decoder, @connection_manager, options)
        pb = AsynchronousPreparedStatementBatch.new(self, b)
        if block_given?
          yield pb
          pb.execute
        else
          pb
        end
      end

      # @private
      def prepare(connection)
        prepare_request = Protocol::PrepareRequest.new(@cql)
        f = @request_runner.execute(connection, prepare_request) do |response|
          connection[self] = response.id
          unless @raw_metadata
            # NOTE: this is not thread safe, but the worst that could happen
            # is that we assign the same data multiple times
            @raw_metadata = response.metadata
            @metadata = ResultMetadata.new(@raw_metadata)
            @raw_result_metadata = response.result_metadata
            if @raw_result_metadata
              @result_metadata = ResultMetadata.new(@raw_result_metadata)
            end
          end
          hex_id = response.id.each_byte.map { |x| x.to_s(16).rjust(2, '0') }.join('')
          @logger.debug('Statement %s prepared on node %s (%s:%d)' % [hex_id, connection[:host_id].to_s, connection.host, connection.port])
        end
        f.map(self)
      end

      # @private
      def add_to_batch(batch, connection, bound_args)
        statement_id = connection[self]
        unless statement_id
          raise NotPreparedError
        end
        unless bound_args.size == @raw_metadata.size
          raise ArgumentError, "Expected #{@raw_metadata.size} arguments, got #{bound_args.size}"
        end
        batch.add_prepared(statement_id, @raw_metadata, bound_args)
      end

      private

      def run(args, connection)
        bound_args = args.shift(@raw_metadata.size)
        unless bound_args.size == @raw_metadata.size && args.size <= 1
          raise ArgumentError, "Expected #{@raw_metadata.size} arguments, got #{bound_args.size}"
        end
        options = @execute_options_decoder.decode_options(args.last)
        statement_id = connection[self]
        request_metadata = @raw_result_metadata.nil?
        request = Protocol::ExecuteRequest.new(statement_id, @raw_metadata, bound_args, options[:consistency], request_metadata, options[:trace])
        @request_runner.execute(connection, request, options[:timeout], @raw_result_metadata)
      end
    end
  end
end