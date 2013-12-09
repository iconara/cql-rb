# encoding: utf-8
require 'lz4-ruby'

module Cql
  module Protocol
    class Request
      include Encoding

      attr_reader :opcode

      def initialize(opcode)
        @opcode = opcode
      end

      def encode_frame(stream_id=0, buffer=ByteBuffer.new, enable_compression)
        raise InvalidStreamIdError, 'The stream ID must be between 0 and 127' unless 0 <= stream_id && stream_id < 128

        buffer.discard(buffer.length)
        write(buffer)
        size = buffer.length

        body = nil
        # don't bother to compress anything < 64 bytes
        compress = 0
        if size > 64 and enable_compression
          compress = 1
          body = buffer.read(size)
          # Skip header from lz4-ruby.
          body = LZ4Internal::compress("", body, body.length)

          body = [size].pack(Formats::INT_FORMAT) + body
        else
          body = buffer.read(size)
        end

        s = body.length
        buffer << [1, compress, stream_id, opcode, body.length].pack(Formats::HEADER_FORMAT)
        buffer << body
        buffer
      end

      def self.change_stream_id(new_stream_id, buffer, offset=0)
        buffer.update(offset + 2, new_stream_id.chr)
      end
    end
  end
end
