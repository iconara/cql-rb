# encoding: utf-8

module Cql
  module Protocol
    class AuthenticateResponse < Response
      attr_reader :authentication_class

      def self.decode!(buffer, trace_id=nil)
        new(read_string!(buffer))
      end

      def initialize(authentication_class)
        @authentication_class = authentication_class
      end

      def to_s
        %(AUTHENTICATE #{authentication_class})
      end
    end
  end
end
