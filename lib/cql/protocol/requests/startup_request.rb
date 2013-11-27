# encoding: utf-8

module Cql
  module Protocol
    class StartupRequest < Request
      def initialize(cql_version='3.0.0', compression=nil)
        super(1)
        @arguments = {CQL_VERSION => cql_version}
        @arguments[COMPRESSION] = compression if compression
      end

      # Disable compression for startup request.
      def encode_frame(stream_id=0, buffer=ByteBuffer.new, enable_compression)
        super(stream_id, buffer, false)
      end

      def write(io)
        write_string_map(io, @arguments)
      end

      def to_s
        %(STARTUP #@arguments)
      end

      private

      CQL_VERSION = 'CQL_VERSION'.freeze
      COMPRESSION = 'COMPRESSION'.freeze
    end
  end
end
