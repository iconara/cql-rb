# encoding: utf-8

module Cql
  module Protocol
    class EventResponse < ResultResponse
      def self.decode!(buffer, trace_id=nil)
        type = read_string!(buffer)
        case type
        when SchemaChangeEventResponse::TYPE
          SchemaChangeEventResponse.decode!(buffer, trace_id)
        when StatusChangeEventResponse::TYPE
          StatusChangeEventResponse.decode!(buffer, trace_id)
        when TopologyChangeEventResponse::TYPE
          TopologyChangeEventResponse.decode!(buffer, trace_id)
        else
          raise UnsupportedEventTypeError, %(Unsupported event type: "#{type}")
        end
      end
    end
  end
end
