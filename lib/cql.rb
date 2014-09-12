# encoding: utf-8

require 'ione'


module Cql
  CqlError = Class.new(StandardError)
  IoError = Ione::IoError

  # @private
  Promise = Ione::Promise

  # @private
  Future = Ione::Future

  # @private
  Io = Ione::Io
end

CqlArgumentError = Class.new(ArgumentError)
InvalidUuidError = Class.new(CqlArgumentError)

require 'cql/uuid'
require 'cql/time_uuid'
require 'cql/compression'
require 'cql/protocol'
require 'cql/auth'
require 'cql/client'
