# encoding: utf-8

module Cql
  module Protocol
    class QueryRequest < Request
      attr_reader :cql, :consistency

      def initialize(cql, values, consistency, trace=false)
        raise ArgumentError, %(No CQL given!) unless cql
        raise ArgumentError, %(No such consistency: #{consistency.inspect}) if consistency.nil? || !CONSISTENCIES.include?(consistency)
        super(7, trace)
        @cql = cql
        @values = values || NO_VALUES
        @encoded_values = encode_values
        @consistency = consistency
      end

      def write(protocol_version, io)
        write_long_string(io, @cql)
        write_consistency(io, @consistency)
        if protocol_version > 1
          if @values.size > 0
            io << VALUES_FLAG
            io << @encoded_values
          else
            io << NO_FLAGS
          end
        end
        io
      end

      def to_s
        %(QUERY "#@cql" #{@consistency.to_s.upcase})
      end

      def eql?(rq)
        self.class === rq && rq.cql.eql?(self.cql) && rq.consistency.eql?(self.consistency)
      end
      alias_method :==, :eql?

      def hash
        @h ||= (@cql.hash * 31) ^ consistency.hash
      end

      private

      def encode_values
        buffer = ''
        write_short(buffer, @values.size)
        @values.each do |value|
          type = guess_type(value)
          raise EncodingError, "Could not guess a suitable type for #{value.inspect}" unless type
          TYPE_CONVERTER.to_bytes(buffer, type, value)
        end
        buffer
      end

      def guess_type(value)
        type = TYPE_GUESSES[value.class]
        if type == :map
          pair = value.first
          [type, guess_type(pair[0]), guess_type(pair[1])]
        elsif type == :list
          [type, guess_type(value.first)]
        elsif type == :set
          [type, guess_type(value.first)]
        else
          type
        end
      end

      TYPE_GUESSES = {
        String => :varchar,
        Fixnum => :bigint,
        Float => :double,
        Bignum => :varint,
        BigDecimal => :decimal,
        TrueClass => :boolean,
        FalseClass => :boolean,
        NilClass => :bigint,
        Uuid => :uuid,
        TimeUuid => :uuid,
        IPAddr => :inet,
        Time => :timestamp,
        Hash => :map,
        Array => :list,
        Set => :set,
      }.freeze
      TYPE_CONVERTER = TypeConverter.new
      NO_VALUES = [].freeze
      NO_FLAGS = "\x00".freeze
      VALUES_FLAG = "\x01".freeze
    end
  end
end
