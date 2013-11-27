# encoding: utf-8
require 'lz4-ruby'

module Cql
  module Protocol
    class ResponseFrame
      def initialize(buffer=ByteBuffer.new)
        @headers = FrameHeaders.new(buffer)
        check_complete!
      end

      def stream_id
        @headers && @headers.stream_id
      end

      def header_length
        8
      end

      def body_length
        @headers && @headers.length
      end

      def body
        @body.response
      end

      def complete?
        @body && @body.complete?
      end

      def <<(str)
        if @body
          @body << str
        else
          @headers << str
          check_complete!
        end
      end

      private

      def check_complete!
        if @headers.complete?
          @body = create_body
        end
      end

      def create_body
        body_type = begin
          case @headers.opcode
          when 0x00 then ErrorResponse
          when 0x02 then ReadyResponse
          when 0x03 then AuthenticateResponse
          when 0x06 then SupportedResponse
          when 0x08 then ResultResponse
          when 0x0c then EventResponse
          else
            raise UnsupportedOperationError, "The operation #{@headers.opcode} is not supported"
          end
        end
        compressed = (@headers.flags & 0x01) == 0x01
        FrameBody.new(@headers.buffer, @headers.length, body_type, compressed)
      end

      class FrameHeaders
        attr_reader :buffer, :protocol_version, :stream_id, :opcode, :length, :flags

        def initialize(buffer)
          @buffer = buffer
          check_complete!
        end

        def <<(str)
          @buffer << str
          check_complete!
        end

        def complete?
          !!@protocol_version
        end

        private

        def check_complete!
          if @buffer.length >= 8
            @protocol_version = @buffer.read_byte(true)
            @flags = @buffer.read_byte(true)
            @stream_id = @buffer.read_byte(true)
            @opcode = @buffer.read_byte(true)
            @length = @buffer.read_int
            raise UnsupportedFrameTypeError, 'Request frames are not supported' if @protocol_version > 0
            @protocol_version &= 0x7f
          end
        end
      end

      class FrameBody
        attr_reader :response, :buffer

        def initialize(buffer, length, type, compressed)
          @buffer = buffer
          @length = length
          @type = type
          @compressed = compressed
          check_complete!
        end

        def <<(str)
          @buffer << str
          check_complete!
        end

        def complete?
          !!@response
        end

        private

        def check_complete!
          if @buffer.length >= @length
            if @compressed and @length >= 5
              uncompressedLength = @buffer.read_int
              @length -= 4
              body = @buffer.read(@length)
              if body.length == 0
                body = "\x00\x00"
                uncompressedLength = 0
              end
              begin
                body = LZ4Internal::uncompress(body, body.length, 0, uncompressedLength)
              rescue => e
                puts $!.inspect, $@
                puts body.length, body.bytesize, @length, uncompressedLength
                exit 1
              end
              if body.length != uncompressedLength
                raise DecodingError, "Uncompressed length did not match expected value."
              end
              @buffer.discard(@buffer.length)
              @buffer << body
              @length = body.length
            end
            extra_length = @buffer.length - @length
            @response = @type.decode!(@buffer)
            if @buffer.length > extra_length
              @buffer.discard(@buffer.length - extra_length)
            end
          end
        end
      end
    end
  end
end
