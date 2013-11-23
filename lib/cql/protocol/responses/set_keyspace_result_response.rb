# encoding: utf-8

module Cql
  module Protocol
    class SetKeyspaceResultResponse < ResultResponse
      attr_reader :keyspace

      def initialize(keyspace, trace_id)
        super(trace_id)
        @keyspace = keyspace
      end

      def self.decode!(buffer, trace_id=nil)
        new(read_string!(buffer), trace_id)
      end

      def to_s
        %(RESULT SET_KEYSPACE "#@keyspace")
      end
    end
  end
end
