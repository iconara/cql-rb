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

# TODO: Change the base class for InvalidUuidError to CqlError during the
# next major release - then remove the CqlArgumentError base class because it
# is only a placeholder for organizational purposes.
CqlArgumentError = Class.new(ArgumentError)
InvalidUuidError = Class.new(CqlArgumentError)

require 'cql/uuid'
require 'cql/time_uuid'
require 'cql/compression'
require 'cql/protocol'
require 'cql/auth'
require 'cql/client'
