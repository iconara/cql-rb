require 'date'
require 'time'

module Cql
  module Sanitize

    class UnescapableObjectError < Cql::CqlError; end
    class InvalidBindVariableError < Cql::CqlError; end

    def self.sanitize(statement, *variables)
      variables = variables.dup
      expected = statement.count('?')

      raise InvalidBindVariableError, "Wrong number of bound variables (statement expected #{expected}, was #{variables.size})" if expected != variables.size

      statement.gsub(/\?/) { cast(variables.shift) }
    end

    private

    def self.quote(string)
      "'" + string.gsub("'", "''") + "'"
    end

    def self.cast(obj)
      case obj
      when Array
        obj.map { |member| cast(member) }.join(',')
      when Hash
        obj.map do |key, value|
          [cast(key), cast(value)].join(':')
        end.join(',')
      when Numeric
        obj
      when Date
        quote(obj.strftime('%Y-%m-%d'))
      when Time
        (obj.to_f * 1000).to_i
      when Cql::Uuid
        obj.to_s
      when String
        if obj.encoding == ::Encoding::BINARY
          '0x' + obj.unpack('H*').first
        else
          quote(obj.encode(::Encoding::UTF_8))
        end
      else
        quote(obj.to_s.dup.force_encoding(::Encoding::BINARY))
      end
    end
  end
end