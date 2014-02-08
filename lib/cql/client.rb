# encoding: utf-8

module Cql
  # This error type represents errors sent by the server, the `code` attribute
  # can be used to find the exact type, and `cql` contains the request's CQL,
  # if any. `message` contains the human readable error message sent by the
  # server.
  class QueryError < CqlError
    attr_reader :code, :cql, :details

    def initialize(code, message, cql=nil, details=nil)
      super(message)
      @code = code
      @cql = cql
      @details = details
    end
  end

  NotConnectedError = Class.new(CqlError)
  TimeoutError = Class.new(CqlError)
  ClientError = Class.new(CqlError)
  AuthenticationError = Class.new(ClientError)
  IncompleteTraceError = Class.new(ClientError)
  UnsupportedProtocolVersionError = Class.new(ClientError)
  NotPreparedError = Class.new(ClientError)

  # A CQL client manages connections to one or more Cassandra nodes and you use
  # it run queries, insert and update data.
  #
  # Client instances are threadsafe.
  #
  # See {Cql::Client::Client} for the full client API, or {Cql::Client.connect}
  # for the options available when connecting.
  #
  # @example Connecting and changing to a keyspace
  #   # create a client and connect to two Cassandra nodes
  #   client = Cql::Client.connect(hosts: %w[node01.cassandra.local node02.cassandra.local])
  #   # change to a keyspace
  #   client.use('stuff')
  #
  # @example Query for data
  #   rows = client.execute('SELECT * FROM things WHERE id = 2')
  #   rows.each do |row|
  #     p row
  #   end
  #
  # @example Inserting and updating data
  #   client.execute("INSERT INTO things (id, value) VALUES (4, 'foo')")
  #   client.execute("UPDATE things SET value = 'bar' WHERE id = 5")
  #
  # @example Prepared statements
  #   statement = client.prepare('INSERT INTO things (id, value) VALUES (?, ?)')
  #   statement.execute(9, 'qux')
  #   statement.execute(8, 'baz')
  module Client
    InvalidKeyspaceNameError = Class.new(ClientError)

    # Create a new client and connect to Cassandra.
    #
    # By default the client will connect to localhost port 9042, which can be
    # overridden with the `:hosts` and `:port` options, respectively. Once
    # connected to the hosts given in `:hosts` the rest of the nodes in the
    # cluster will automatically be discovered and connected to.
    #
    # If you have a multi data center setup the client will connect to all nodes
    # in the data centers where the nodes you pass to `:hosts` are located. So
    # if you only want to connect to nodes in one data center, make sure that
    # you only specify nodes in that data center in `:hosts`.
    #
    # The connection will succeed if at least one node is up and accepts the
    # connection. Nodes that don't respond within the specified timeout, or
    # where the connection initialization fails for some reason, are ignored.
    #
    # @param [Hash] options
    # @option options [Array<String>] :hosts (['localhost']) One or more
    #   hostnames used as seed nodes when connecting. Duplicates will be removed.
    # @option options [String] :host ('localhost') A comma separated list of 
    #   hostnames to use as seed nodes. This is a backwards-compatible version
    #   of the :hosts option, and is deprecated.
    # @option options [String] :port (9042) The port to connect to, this port
    #   will be used for all nodes. Because the `system.peers` table does not
    #   contain the port that the nodes are listening on, the port must be the
    #   same for all nodes.
    # @option options [Integer] :connection_timeout (5) Max time to wait for a
    #   connection, in seconds.
    # @option options [String] :keyspace The keyspace to change to immediately
    #   after all connections have been established, this is optional.
    # @option options [Integer] :connections_per_node (1) The number of
    #   connections to open to each node. Each connection can have 128
    #   concurrent requests, so unless you have a need for more than that (times
    #   the number of nodes in your cluster), leave this option at its default.
    # @option options [Integer] :default_consistency (:quorum) The consistency
    #   to use unless otherwise specified. Consistency can also be specified on
    #   a per-request basis.
    # @option options [Cql::Compression::Compressor] :compressor An object that
    #   can compress and decompress frames. By specifying this option frame
    #   compression will be enabled. If the server does not support compression
    #   or the specific compression algorithm specified by the compressor,
    #   compression will not be enabled and a warning will be logged.
    # @option options [Integer] :logger If you want the client to log
    #   significant events pass an object implementing the standard Ruby logger
    #   interface (e.g. quacks like `Logger` from the standard library) with
    #   this option.
    # @raise Cql::Io::ConnectionError when a connection couldn't be established
    #   to any node
    # @return [Cql::Client::Client]
    def self.connect(options={})
      SynchronousClient.new(AsynchronousClient.new(options)).connect
    end

    class Client
      # @!method connect
      #
      # Connect to all nodes. See {Cql::Client.connect} for the full
      # documentation.
      #
      # This method needs to be called before any other. Calling it again will
      # have no effect.
      #
      # @see Cql::Client.connect
      # @return [Cql::Client]

      # @!method close
      #
      # Disconnect from all nodes.
      #
      # @return [Cql::Client]

      # @!method connected?
      #
      # Returns whether or not the client is connected.
      #
      # @return [true, false]

      # @!method keyspace
      #
      # Returns the name of the current keyspace, or `nil` if no keyspace has been
      # set yet.
      #
      # @return [String]

      # @!method use(keyspace)
      #
      # Changes keyspace by sending a `USE` statement to all connections.
      #
      # The the second parameter is meant for internal use only.
      #
      # @param [String] keyspace
      # @raise [Cql::NotConnectedError] raised when the client is not connected
      # @return [nil]

      # @!method execute(cql, *values, options_or_consistency={})
      #
      # Execute a CQL statement, optionally passing bound values.
      #
      # When passing bound values the request encoder will have to guess what
      # types to encode the values as. For most types this will be no problem,
      # but for integers and floating point numbers the larger size will be
      # chosen (e.g. `BIGINT` and `DOUBLE` and not `INT` and `FLOAT`). You can
      # override the guessing with the `:type_hint` option. Don't use on-the-fly
      # bound values when you will issue the request multiple times, prepared
      # statements are almost always a better choice.
      #
      # @note On-the-fly bound values are not supported in Cassandra 1.2
      #
      # @example A simple CQL query
      #   result = client.execute("SELECT * FROM users WHERE user_name = 'sue'")
      #   result.each do |row|
      #     p row
      #   end
      #
      # @example Using on-the-fly bound values
      #   client.execute('INSERT INTO users (user_name, full_name) VALUES (?, ?)', 'sue', 'Sue Smith')
      #
      # @example Using on-the-fly bound values with type hints
      #   client.execute('INSERT INTO users (user_name, age) VALUES (?, ?)', 'sue', 33, type_hints: [nil, :int])
      #
      # @example Specifying the consistency as a symbol
      #   client.execute("UPDATE users SET full_name = 'Sue S. Smith' WHERE user_name = 'sue'", consistency: :one)
      #
      # @example Specifying the consistency and other options
      #   client.execute("SELECT * FROM users", consistency: :all, timeout: 1.5)
      #
      # @example Activating tracing for a query
      #   result = client.execute("SELECT * FROM users", tracing: true)
      #   p result.trace_id
      #
      # @param [String] cql
      # @param [Array] values Values to bind to any binding markers in the
      #   query (i.e. "?" placeholders) -- using this feature is similar to
      #   using a prepared statement, but without the type checking. The client
      #   needs to guess which data types to encode the values as, and will err
      #   on the side of caution, using types like BIGINT instead of INT for
      #   integers, and DOUBLE instead of FLOAT for floating point numbers. It
      #   is not recommended to use this feature for anything but convenience,
      #   and the algorithm used to guess types is to be considered experimental.
      # @param [Hash] options_or_consistency Either a consistency as a symbol
      #   (e.g. `:quorum`), or a options hash (see below). Passing a symbol is
      #   equivalent to passing the options `consistency: <symbol>`.
      # @option options_or_consistency [Symbol] :consistency (:quorum) The
      #   consistency to use for this query.
      # @option options_or_consistency [Symbol] :serial_consistency (nil) The
      #   consistency to use for conditional updates (`:serial` or
      #   `:local_serial`), see the CQL documentation for the semantics of
      #   serial consistencies and conditional updates. The default is assumed
      #   to be `:serial` by the server if none is specified. Ignored for non-
      #   conditional queries.
      # @option options_or_consistency [Integer] :timeout (nil) How long to wait
      #   for a response. If this timeout expires a {Cql::TimeoutError} will
      #   be raised.
      # @option options_or_consistency [Boolean] :trace (false) Request tracing
      #   for this request. See {Cql::Client::QueryResult} and
      #   {Cql::Client::VoidResult} for how to retrieve the tracing data.
      # @option options_or_consistency [Array] :type_hints (nil) When passing
      #   on-the-fly bound values the request encoder will have to guess what
      #   types to encode the values as. Using this option you can give it hints
      #   and avoid it guessing wrong. The hints must be an array that has the
      #   same number of arguments as the number of bound values, and each
      #   element should be the type of the corresponding value, or nil if you
      #   prefer the encoder to guess. The types should be provided as lower
      #   case symbols, e.g. `:int`, `:time_uuid`, etc.
      # @raise [Cql::NotConnectedError] raised when the client is not connected
      # @raise [Cql::TimeoutError] raised when a timeout was specified and no
      #   response was received within the timeout.
      # @raise [Cql::QueryError] raised when the CQL has syntax errors or for
      #   other situations when the server complains.
      # @return [nil, Cql::Client::QueryResult, Cql::Client::VoidResult] Some
      #   queries have no result and return `nil`, but `SELECT` statements
      #   return an `Enumerable` of rows (see {Cql::Client::QueryResult}), and
      #   `INSERT` and `UPDATE` return a similar type
      #   (see {Cql::Client::VoidResult}).

      # @!method prepare(cql)
      #
      # Returns a prepared statement that can be run over and over again with
      # different values.
      #
      # @see Cql::Client::PreparedStatement
      # @param [String] cql The CQL to prepare
      # @raise [Cql::NotConnectedError] raised when the client is not connected
      # @raise [Cql::Io::IoError] raised when there is an IO error, for example
      #   if the server suddenly closes the connection
      # @raise [Cql::QueryError] raised when there is an error on the server
      #   side, for example when you specify a malformed CQL query
      # @return [Cql::Client::PreparedStatement] an object encapsulating the
      #   prepared statement

      # @!method batch(type=:logged, options={})
      #
      # Yields a batch when called with a block. The batch is automatically
      # executed at the end of the block and the result is returned.
      #
      # Returns a batch when called wihtout a block. The batch will remember
      # the options given and merge these with any additional options given
      # when {Cql::Client::Batch#execute} is called.
      #
      # Please note that the batch object returned by this method _is not thread
      # safe_.
      #
      # The type parameter can be ommitted and the options can then be given
      # as first parameter.
      #
      # @example Executing queries in a batch
      #   client.batch do |batch|
      #     batch.add(%(INSERT INTO metrics (id, time, value) VALUES (1234, NOW(), 23423)))
      #     batch.add(%(INSERT INTO metrics (id, time, value) VALUES (2346, NOW(), 13)))
      #     batch.add(%(INSERT INTO metrics (id, time, value) VALUES (2342, NOW(), 2367)))
      #     batch.add(%(INSERT INTO metrics (id, time, value) VALUES (4562, NOW(), 1231)))
      #   end
      #
      # @example Using the returned batch object
      #   batch = client.batch(:counter, trace: true)
      #   batch.add('UPDATE counts SET value = value + ? WHERE id = ?', 4, 87654)
      #   batch.add('UPDATE counts SET value = value + ? WHERE id = ?', 3, 6572)
      #   result = batch.execute(timeout: 10)
      #   puts result.trace_id
      #
      # @example Providing type hints for on-the-fly bound values
      #   batch = client.batch
      #   batch.add('UPDATE counts SET value = value + ? WHERE id = ?', 4, type_hints: [:int])
      #   batch.execute
      #
      # @see Cql::Client::Batch
      # @param [Symbol] type the type of batch, must be one of `:logged`,
      #   `:unlogged` and `:counter`. The precise meaning of these  is defined
      #   in the CQL specification.
      # @yieldparam [Cql::Client::Batch] batch the batch
      # @return [Cql::Client::VoidResult, Cql::Client::Batch] when no block is
      #   given the batch is returned, when a block is given the result of
      #   executing the batch is returned (see {Cql::Client::Batch#execute}).
    end

    class PreparedStatement
      # Metadata describing the bound values
      #
      # @return [ResultMetadata]
      attr_reader :metadata

      # Metadata about the result (i.e. rows) that is returned when executing
      # this prepared statement.
      #
      # @return [ResultMetadata]
      attr_reader :result_metadata

      # Execute the prepared statement with a list of values to be bound to the
      # statements parameters.
      #
      # The number of arguments must equal the number of bound parameters. You
      # can also specify options as the last argument, or a symbol as a shortcut
      # for just specifying the consistency.
      #
      # Because you can specify options, or not, there is an edge case where if
      # the last parameter of your prepared statement is a map, and you forget
      # to specify a value for your map, the options will end up being sent to
      # Cassandra. Most other cases when you specify the wrong number of
      # arguments should result in an `ArgumentError` or `TypeError` being
      # raised.
      #
      # @param args [Array] the values for the bound parameters. The last
      #   argument can also be an options hash or a symbol (as a shortcut for
      #   specifying the consistency), see {Cql::Client::Client#execute} for
      #   full details.
      # @raise [ArgumentError] raised when number of argument does not match
      #   the number of parameters needed to be bound to the statement.
      # @raise [Cql::NotConnectedError] raised when the client is not connected
      # @raise [Cql::Io::IoError] raised when there is an IO error, for example
      #   if the server suddenly closes the connection
      # @raise [Cql::QueryError] raised when there is an error on the server side
      # @return [nil, Cql::Client::QueryResult, Cql::Client::VoidResult] Some
      #   queries have no result and return `nil`, but `SELECT` statements
      #   return an `Enumerable` of rows (see {Cql::Client::QueryResult}), and
      #   `INSERT` and `UPDATE` return a similar type
      #   (see {Cql::Client::VoidResult}).
      def execute(*args)
      end
    end

    class Batch
      # @!method add(cql_or_prepared_statement, *bound_values)
      #
      # Add a query or a prepared statement to the batch.
      #
      # @example Adding a mix of statements to a batch
      #   batch.add(%(UPDATE people SET name = 'Miriam' WHERE id = 3435))
      #   batch.add(%(UPDATE people SET name = ? WHERE id = ?), 'Miriam', 3435)
      #   batch.add(prepared_statement, 'Miriam', 3435)
      #
      # @param [String, Cql::Client::PreparedStatement] cql_or_prepared_statement
      #   a CQL string or a prepared statement object (obtained through
      #   {Cql::Client::Client#prepare})
      # @param [Array] bound_values a list of bound values -- only applies when
      #   adding prepared statements and when there are binding markers in the
      #   given CQL. If the last argument is a hash and it has the key
      #   `:type_hints` this will be passed as type hints to the request encoder
      #   (if the last argument is any other hash it will be assumed to be a
      #   bound value of type MAP). See {Cql::Client::Client#execute} for more
      #   info on type hints.
      # @return [nil]

      # @!method execute(options={})
      #
      # Execute the batch and return the result.
      #
      # @param options [Hash] an options hash or a symbol (as a shortcut for
      #   specifying the consistency), see {Cql::Client::Client#execute} for
      #   full details about how this value is interpreted.
      # @raise [Cql::QueryError] raised when there is an error on the server side
      # @raise [Cql::NotPreparedError] raised in the unlikely event that a
      #   prepared statement was not prepared on the chosen connection
      # @return [Cql::Client::VoidResult] a batch always returns a void result
    end

    class PreparedStatementBatch
      # @!method add(*bound_values)
      #
      # Add the statement to the batch with the specified bound values.
      #
      # @param [Array] bound_values the values to bind to the added statement,
      #   see {Cql::Client::PreparedStatement#execute}.
      # @return [nil]

      # @!method execute(options={})
      #
      # Execute the batch and return the result.
      #
      # @raise [Cql::QueryError] raised when there is an error on the server side
      # @raise [Cql::NotPreparedError] raised in the unlikely event that a
      #   prepared statement was not prepared on the chosen connection
      # @return [Cql::Client::VoidResult] a batch always returns a void result
    end
  end
end

require 'cql/client/connection_manager'
require 'cql/client/connector'
require 'cql/client/null_logger'
require 'cql/client/column_metadata'
require 'cql/client/result_metadata'
require 'cql/client/query_result'
require 'cql/client/void_result'
require 'cql/client/query_trace'
require 'cql/client/execute_options_decoder'
require 'cql/client/keyspace_changer'
require 'cql/client/asynchronous_client'
require 'cql/client/asynchronous_prepared_statement'
require 'cql/client/synchronous_client'
require 'cql/client/synchronous_prepared_statement'
require 'cql/client/batch'
require 'cql/client/request_runner'
require 'cql/client/authenticators'
require 'cql/client/peer_discovery'