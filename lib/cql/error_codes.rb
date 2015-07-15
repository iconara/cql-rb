# encoding: utf-8

module Cql
  module ErrorCodes
    # Something unexpected happened. This indicates a server-side bug.
    SERVER_ERROR = 0x0000

    # Some client message triggered a protocol violation (for instance a QUERY
    # message is sent before a STARTUP one has been sent).
    PROTOCOL_ERROR = 0x000A

    # CREDENTIALS request failed because Cassandra did not accept the provided credentials.
    BAD_CREDENTIALS = 0x0100

    # Unavailable exception.
    #
    # Details:
    #
    # * `:cl` - The consistency level of the query having triggered the exception.
    # * `:required` - An int representing the number of nodes that should be alive to respect `:cl`.
    # * `:alive` - An int representing the number of replica that were known to be
    #   alive when the request has been processed (since an unavailable
    #   exception has been triggered, there will be `:alive` < `:required`.
    UNAVAILABLE = 0x1000

    # The request cannot be processed because the coordinator node is overloaded.
    OVERLOADED = 0x1001

    # The request was a read request but the coordinator node is bootstrapping.
    IS_BOOTSTRAPPING = 0x1002

    # Error during a truncation error.
    TRUNCATE_ERROR = 0x1003

    # Timeout exception during a write request.
    #
    # Details:
    #
    # * `:cl` - The consistency level of the query having triggered the exception.
    # * `:received` - An int representing the number of nodes having acknowledged the request.
    # * `:blockfor` - The number of replica whose acknowledgement is required to achieve `:cl`.
    # * `:write_type` - A string that describe the type of the write that timeouted. The value of that string can be one of:
    #   - `"SIMPLE"`: the write was a non-batched non-counter write.
    #   - `"BATCH"`: the write was a (logged) batch write. If this type is received, it means the batch log
    #     has been successfully written (otherwise a `"BATCH_LOG"` type would have been send instead).
    #   - `"UNLOGGED_BATCH"`: the write was an unlogged batch. Not batch log write has been attempted.
    #   - `"COUNTER"`: the write was a counter write (batched or not).
    #   - `"BATCH_LOG"`: the timeout occured during the write to the batch log when a (logged) batch write was requested.
    WRITE_TIMEOUT = 0x1100

    # Timeout exception during a read request.
    #
    # Details:
    #
    # * `:cl` - The consistency level of the query having triggered the exception
    # * `:received` -  An int representing the number of nodes having answered the request.
    # * `:blockfor` -  The number of replica whose response is required to achieve `:cl`.
    #   Please note that it is possible to have `:received` >= `:blockfor` if
    #   `:data_present` is false. And also in the (unlikely) case were `:cl` is
    #   achieved but the coordinator node timeout while waiting for read-repair
    #   acknowledgement.
    # * `:data_present` - If `true`, it means the replica that was asked for data has not responded.
    READ_TIMEOUT = 0x1200

    # The submitted query has a syntax error.
    SYNTAX_ERROR = 0x2000

    # The logged user doesn't have the right to perform the query.
    UNAUTHORIZED = 0x2100

    # The query is syntactically correct but invalid.
    INVALID = 0x2200

    # The query is invalid because of some configuration issue.
    CONFIG_ERROR = 0x2300

    # The query attempted to create a keyspace or a table that was already existing.
    #
    # Details:
    #
    # * `:ks` - A string representing either the keyspace that already exists, or the
    #   keyspace in which the table that already exists is.
    # * `:table` -  A string representing the name of the table that already exists. If the
    #   query was attempting to create a keyspace, `:table` will be present but
    #   will be the empty string.
    ALREADY_EXISTS = 0x2400

    # Can be thrown while a prepared statement tries to be executed if the
    # provide prepared statement ID is not known by this host.
    #
    # Details:
    #
    # * `:id` - The unknown ID.
    UNPREPARED = 0x2500
  end
end
