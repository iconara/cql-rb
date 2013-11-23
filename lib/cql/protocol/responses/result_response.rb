# encoding: utf-8

module Cql
  module Protocol
    class ResultResponse < Response
      attr_reader :trace_id

      def initialize(trace_id)
        @trace_id = trace_id
      end

      def self.decode!(buffer, trace_id=nil)
        kind = read_int!(buffer)
        case kind
        when 0x01
          VoidResultResponse.decode!(buffer, trace_id)
        when 0x02
          RowsResultResponse.decode!(buffer, trace_id)
        when 0x03
          SetKeyspaceResultResponse.decode!(buffer, trace_id)
        when 0x04
          PreparedResultResponse.decode!(buffer, trace_id)
        when 0x05
          SchemaChangeResultResponse.decode!(buffer, trace_id)
        else
          raise UnsupportedResultKindError, %(Unsupported result kind: #{kind})
        end
      end

      def void?
        false
      end
    end
  end
end
