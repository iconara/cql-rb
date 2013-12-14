# encoding: utf-8

require 'spec_helper'


module Cql
  module Client
    describe AsynchronousClient do
      let :client do
        described_class.new(connection_options)
      end

      let :connection_options do
        {:host => 'example.com', :port => 12321, :io_reactor => io_reactor, :logger => logger}
      end

      let :io_reactor do
        FakeIoReactor.new
      end

      let :logger do
        NullLogger.new
      end

      def connections
        io_reactor.connections
      end

      def last_connection
        connections.last
      end

      def requests
        last_connection.requests
      end

      def last_request
        requests.last
      end

      def handle_request(&handler)
        @request_handler = handler
      end

      before do
        io_reactor.on_connection do |connection|
          connection.handle_request do |request, timeout|
            response = nil
            if @request_handler
              response = @request_handler.call(request, connection, proc { connection.default_request_handler(request) }, timeout)
            end
            unless response
              response = connection.default_request_handler(request)
            end
            response
          end
        end
      end

      shared_context 'peer discovery setup' do
        let :local_info do
          {
            'data_center' => 'dc1',
            'host_id' => nil,
          }
        end

        let :local_metadata do
          [
            ['system', 'local', 'data_center', :text],
            ['system', 'local', 'host_id', :uuid],
          ]
        end

        let :peer_metadata do
          [
            ['system', 'peers', 'peer', :inet],
            ['system', 'peers', 'data_center', :varchar],
            ['system', 'peers', 'host_id', :uuid],
            ['system', 'peers', 'rpc_address', :inet],
          ]
        end

        let :data_centers do
          Hash.new('dc1')
        end

        let :additional_nodes do
          Array.new(5) { IPAddr.new("127.0.#{rand(255)}.#{rand(255)}") }
        end

        let :bind_all_rpc_addresses do
          false
        end

        let :min_peers do
          [2]
        end

        before do
          uuid_generator = TimeUuid::Generator.new
          additional_rpc_addresses = additional_nodes.dup
          io_reactor.on_connection do |connection|
            connection[:spec_host_id] = uuid_generator.next
            connection[:spec_data_center] = data_centers[connection.host]
            connection.handle_request do |request|
              case request
              when Protocol::StartupRequest
                Protocol::ReadyResponse.new
              when Protocol::QueryRequest
                case request.cql
                when /FROM system\.local/
                  row = {'host_id' => connection[:spec_host_id], 'data_center' => connection[:spec_data_center]}
                  Protocol::RowsResultResponse.new([row], local_metadata, nil)
                when /FROM system\.peers/
                  other_host_ids = connections.reject { |c| c[:spec_host_id] == connection[:spec_host_id] }.map { |c| c[:spec_host_id] }
                  until other_host_ids.size >= min_peers[0]
                    other_host_ids << uuid_generator.next
                  end
                  rows = other_host_ids.map do |host_id|
                    ip = additional_rpc_addresses.shift
                    {
                      'peer' => ip,
                      'host_id' => host_id,
                      'data_center' => data_centers[ip],
                      'rpc_address' => bind_all_rpc_addresses ? IPAddr.new('0.0.0.0') : ip
                    }
                  end
                  Protocol::RowsResultResponse.new(rows, peer_metadata, nil)
                end
              end
            end
          end
        end
      end

      describe '#connect' do
        it 'connects' do
          client.connect.value
          connections.should have(1).item
        end

        it 'connects only once' do
          client.connect.value
          client.connect.value
          connections.should have(1).item
        end

        context 'when connecting to multiple hosts' do
          before do
            client.close.value
            io_reactor.stop.value
          end

          it 'connects to all hosts' do
            c = described_class.new(connection_options.merge(hosts: %w[h1.example.com h2.example.com h3.example.com]))
            c.connect.value
            connections.should have(3).items
          end

          it 'connects to all hosts, when given as a comma-sepatated string' do
            c = described_class.new(connection_options.merge(host: 'h1.example.com,h2.example.com,h3.example.com'))
            c.connect.value
            connections.should have(3).items
          end

          it 'only connects to each host once' do
            c = described_class.new(connection_options.merge(hosts: %w[h1.example.com h2.example.com h2.example.com]))
            c.connect.value
            connections.should have(2).items
          end

          it 'connects to each host the specifie number of times' do
            c = described_class.new(connection_options.merge(hosts: %w[h1.example.com h2.example.com], connections_per_node: 3))
            c.connect.value
            connections.should have(6).items
          end

          it 'succeeds even if only one of the connections succeeded' do
            io_reactor.node_down('h1.example.com')
            io_reactor.node_down('h3.example.com')
            c = described_class.new(connection_options.merge(hosts: %w[h1.example.com h2.example.com h2.example.com]))
            c.connect.value
            connections.should have(1).items
          end

          it 'fails when all nodes are down' do
            io_reactor.node_down('h1.example.com')
            io_reactor.node_down('h2.example.com')
            io_reactor.node_down('h3.example.com')
            c = described_class.new(connection_options.merge(hosts: %w[h1.example.com h2.example.com h2.example.com]))
            expect { c.connect.value }.to raise_error(Io::ConnectionError)
          end
        end

        it 'returns itself' do
          client.connect.value.should equal(client)
        end

        it 'connects to the right host and port' do
          client.connect.value
          last_connection.host.should == 'example.com'
          last_connection.port.should == 12321
        end

        it 'connects with the default connection timeout' do
          client.connect.value
          last_connection.timeout.should == 10
        end

        it 'is not in a keyspace' do
          client.connect.value
          client.keyspace.should be_nil
        end

        it 'enables compression when a compressor is specified' do
          handle_request do |request|
            case request
            when Protocol::OptionsRequest
              Protocol::SupportedResponse.new('CQL_VERSION' => %w[3.0.0], 'COMPRESSION' => %w[lz4 snappy])
            end
          end
          compressor = double(:compressor, algorithm: 'lz4')
          c = described_class.new(connection_options.merge(compressor: compressor))
          c.connect.value
          request = requests.find { |rq| rq.is_a?(Protocol::StartupRequest) }
          request.options.should include('COMPRESSION' => 'lz4')
        end

        it 'changes to the keyspace given as an option' do
          c = described_class.new(connection_options.merge(:keyspace => 'hello_world'))
          c.connect.value
          request = requests.find { |rq| rq == Protocol::QueryRequest.new('USE hello_world', :one) }
          request.should_not be_nil, 'expected a USE request to have been sent'
        end

        it 'validates the keyspace name before sending the USE command' do
          c = described_class.new(connection_options.merge(:keyspace => 'system; DROP KEYSPACE system'))
          expect { c.connect.value }.to raise_error(InvalidKeyspaceNameError)
          requests.should_not include(Protocol::QueryRequest.new('USE system; DROP KEYSPACE system', :one))
        end

        context 'with automatic peer discovery' do
          include_context 'peer discovery setup'

          it 'connects to the other nodes in the cluster' do
            client.connect.value
            connections.should have(3).items
          end

          context 'when the nodes have 0.0.0.0 as rpc_address' do
            let :bind_all_rpc_addresses do
              true
            end

            it 'falls back on using the peer column' do
              client.connect.value
              connections.should have(3).items
            end
          end

          it 'connects to the other nodes in the same data center' do
            data_centers[additional_nodes[1]] = 'dc2'
            client.connect.value
            connections.should have(2).items
          end

          it 'connects to the other nodes in same data centers as the seed nodes' do
            data_centers['host2'] = 'dc2'
            data_centers[additional_nodes[1]] = 'dc2'
            c = described_class.new(connection_options.merge(hosts: %w[host1 host2]))
            c.connect.value
            connections.should have(3).items
          end

          it 'only connects to the other nodes in the cluster it is not already connected do' do
            c = described_class.new(connection_options.merge(hosts: %w[host1 host2]))
            c.connect.value
            connections.should have(3).items
          end

          it 'handles the case when it is already connected to all nodes' do
            c = described_class.new(connection_options.merge(hosts: %w[host1 host2 host3 host4]))
            c.connect.value
            connections.should have(4).items
          end

          it 'accepts that some nodes are down' do
            io_reactor.node_down(additional_nodes.first.to_s)
            client.connect.value
            connections.should have(2).items
          end
        end

        it 're-raises any errors raised' do
          io_reactor.stub(:connect).and_raise(ArgumentError)
          expect { client.connect.value }.to raise_error(ArgumentError)
        end

        it 'is not connected if an error is raised' do
          io_reactor.stub(:connect).and_raise(ArgumentError)
          client.connect.value rescue nil
          client.should_not be_connected
          io_reactor.should_not be_running
        end

        it 'is connected after #connect returns' do
          client.connect.value
          client.should be_connected
        end

        it 'is not connected while connecting' do
          go = false
          io_reactor.stop.value
          io_reactor.before_startup { sleep 0.01 until go }
          client.connect
          begin
            client.should_not be_connected
          ensure
            go = true
          end
        end

        context 'when the server requests authentication' do
          def accepting_request_handler(request, *)
            case request
            when Protocol::StartupRequest
              Protocol::AuthenticateResponse.new('com.example.Auth')
            when Protocol::CredentialsRequest
              Protocol::ReadyResponse.new
            end
          end

          def denying_request_handler(request, *)
            case request
            when Protocol::StartupRequest
              Protocol::AuthenticateResponse.new('com.example.Auth')
            when Protocol::CredentialsRequest
              Protocol::ErrorResponse.new(256, 'No way, José')
            end
          end

          before do
            handle_request(&method(:accepting_request_handler))
          end

          it 'sends credentials' do
            client = described_class.new(connection_options.merge(credentials: {'username' => 'foo', 'password' => 'bar'}))
            client.connect.value
            request = requests.find { |rq| rq == Protocol::CredentialsRequest.new('username' => 'foo', 'password' => 'bar') }
            request.should_not be_nil, 'expected a credentials request to have been sent'
          end

          it 'raises an error when no credentials have been given' do
            client = described_class.new(connection_options)
            expect { client.connect.value }.to raise_error(AuthenticationError)
          end

          it 'raises an error when the server responds with an error to the credentials request' do
            handle_request(&method(:denying_request_handler))
            client = described_class.new(connection_options.merge(credentials: {'username' => 'foo', 'password' => 'bar'}))
            expect { client.connect.value }.to raise_error(AuthenticationError)
          end

          it 'shuts down the client when there is an authentication error' do
            handle_request(&method(:denying_request_handler))
            client = described_class.new(connection_options.merge(credentials: {'username' => 'foo', 'password' => 'bar'}))
            client.connect.value rescue nil
            client.should_not be_connected
            io_reactor.should_not be_running
          end
        end
      end

      describe '#close' do
        it 'closes the connection' do
          client.connect.value
          client.close.value
          io_reactor.should_not be_running
        end

        it 'does nothing when called before #connect' do
          client.close.value
        end

        it 'accepts multiple calls to #close' do
          client.connect.value
          client.close.value
          client.close.value
        end

        it 'returns itself' do
          client.connect.value.close.value.should equal(client)
        end

        it 'fails when the IO reactor stop fails' do
          io_reactor.stub(:stop).and_return(Future.failed(StandardError.new('Bork!')))
          expect { client.close.value }.to raise_error('Bork!')
        end

        it 'cannot be connected again once closed' do
          client.connect.value
          client.close.value
          expect { client.connect.value }.to raise_error(ClientError)
        end
      end

      describe '#use' do
        it 'executes a USE query' do
          handle_request do |request|
            if request.is_a?(Protocol::QueryRequest) && request.cql == 'USE system'
              Protocol::SetKeyspaceResultResponse.new('system', nil)
            end
          end
          client.connect.value
          client.use('system').value
          last_request.should == Protocol::QueryRequest.new('USE system', :one)
        end

        it 'executes a USE query for each connection' do
          client.close.value
          io_reactor.stop.value
          io_reactor.start.value

          c = described_class.new(connection_options.merge(hosts: %w[h1.example.com h2.example.com h3.example.com]))
          c.connect.value

          c.use('system').value
          last_requests = connections.select { |c| c.host =~ /^h\d\.example\.com$/ }.sort_by(&:host).map { |c| c.requests.last }
          last_requests.should == [
            Protocol::QueryRequest.new('USE system', :one),
            Protocol::QueryRequest.new('USE system', :one),
            Protocol::QueryRequest.new('USE system', :one)
          ]
        end

        it 'knows which keyspace it changed to' do
          handle_request do |request|
            if request.is_a?(Protocol::QueryRequest) && request.cql == 'USE system'
              Protocol::SetKeyspaceResultResponse.new('system', nil)
            end
          end
          client.connect.value
          client.use('system').value
          client.keyspace.should == 'system'
        end

        it 'raises an error if the keyspace name is not valid' do
          client.connect.value
          expect { client.use('system; DROP KEYSPACE system').value }.to raise_error(InvalidKeyspaceNameError)
        end

        it 'allows the keyspace name to be quoted' do
          handle_request do |request|
            if request.is_a?(Protocol::QueryRequest) && request.cql == 'USE "system"'
              Protocol::SetKeyspaceResultResponse.new('system', nil)
            end
          end
          client.connect.value
          client.use('"system"').value
          client.keyspace.should == "system"
        end
      end

      describe '#execute' do
        let :cql do
          'UPDATE stuff SET thing = 1 WHERE id = 3'
        end

        before do
          client.connect.value
        end

        it 'asks the connection to execute the query using the default consistency level' do
          client.execute(cql).value
          last_request.should == Protocol::QueryRequest.new(cql, :quorum)
        end

        it 'uses the consistency specified when the client was created' do
          client = described_class.new(connection_options.merge(default_consistency: :all))
          client.connect.value
          client.execute(cql).value
          last_request.should == Protocol::QueryRequest.new(cql, :all)
        end

        it 'uses the consistency given as last argument' do
          client.execute('UPDATE stuff SET thing = 1 WHERE id = 3', :three).value
          last_request.should == Protocol::QueryRequest.new('UPDATE stuff SET thing = 1 WHERE id = 3', :three)
        end

        it 'uses the consistency given as an option' do
          client.execute('UPDATE stuff SET thing = 1 WHERE id = 3', consistency: :local_quorum).value
          last_request.should == Protocol::QueryRequest.new('UPDATE stuff SET thing = 1 WHERE id = 3', :local_quorum)
        end

        context 'with a void CQL query' do
          it 'returns nil' do
            handle_request do |request|
              if request.is_a?(Protocol::QueryRequest) && request.cql =~ /UPDATE/
                Protocol::VoidResultResponse.new(nil)
              end
            end
            result = client.execute('UPDATE stuff SET thing = 1 WHERE id = 3').value
            result.should be_nil
          end
        end

        context 'with a USE query' do
          it 'returns nil' do
            handle_request do |request|
              if request.is_a?(Protocol::QueryRequest) && request.cql == 'USE system'
                Protocol::SetKeyspaceResultResponse.new('system', nil)
              end
            end
            result = client.execute('USE system').value
            result.should be_nil
          end

          it 'knows which keyspace it changed to' do
            handle_request do |request|
              if request.is_a?(Protocol::QueryRequest) && request.cql == 'USE system'
                Protocol::SetKeyspaceResultResponse.new('system', nil)
              end
            end
            client.execute('USE system').value
            client.keyspace.should == 'system'
          end

          it 'detects that one connection changed to a keyspace and changes the others too' do
            client.close.value
            io_reactor.stop.value
            io_reactor.start.value

            handle_request do |request, connection|
              if request.is_a?(Protocol::QueryRequest) && request.cql == 'USE system'
                Protocol::SetKeyspaceResultResponse.new('system', nil)
              end
            end

            c = described_class.new(connection_options.merge(hosts: %w[h1.example.com h2.example.com h3.example.com]))
            c.connect.value

            c.execute('USE system', :one).value
            c.keyspace.should == 'system'

            last_requests = connections.select { |c| c.host =~ /^h\d\.example\.com$/ }.sort_by(&:host).map { |c| c.requests.last }
            last_requests.should == [
              Protocol::QueryRequest.new('USE system', :one),
              Protocol::QueryRequest.new('USE system', :one),
              Protocol::QueryRequest.new('USE system', :one)
            ]
          end
        end

        context 'with an SELECT query' do
          let :rows do
            [['xyz', 'abc'], ['abc', 'xyz'], ['123', 'xyz']]
          end

          let :metadata do
            [['thingies', 'things', 'thing', :text], ['thingies', 'things', 'item', :text]]
          end

          let :result do
            client.execute('SELECT * FROM things').value
          end

          before do
            handle_request do |request|
              if request.is_a?(Protocol::QueryRequest) && request.cql =~ /FROM things/
                Protocol::RowsResultResponse.new(rows, metadata, nil)
              end
            end
          end

          it 'returns an Enumerable of rows' do
            row_count = 0
            result.each do |row|
              row_count += 1
            end
            row_count.should == 3
          end

          context 'with metadata that' do
            it 'has keyspace, table and type information' do
              result.metadata['item'].keyspace.should == 'thingies'
              result.metadata['item'].table.should == 'things'
              result.metadata['item'].column_name.should == 'item'
              result.metadata['item'].type.should == :text
            end

            it 'is an Enumerable' do
              result.metadata.map(&:type).should == [:text, :text]
            end

            it 'is splattable' do
              ks, table, col, type = result.metadata['thing']
              ks.should == 'thingies'
              table.should == 'things'
              col.should == 'thing'
              type.should == :text
            end
          end
        end

        context 'when there is an error creating the request' do
          it 'returns a failed future' do
            f = client.execute('SELECT * FROM stuff', :foo)
            expect { f.value }.to raise_error(ArgumentError)
          end
        end

        context 'when the response is an error' do
          before do
            handle_request do |request|
              if request.is_a?(Protocol::QueryRequest) && request.cql =~ /FROM things/
                Protocol::ErrorResponse.new(0xabcd, 'Blurgh')
              end
            end
          end

          it 'raises an error' do
            expect { client.execute('SELECT * FROM things').value }.to raise_error(QueryError, 'Blurgh')
          end

          it 'decorates the error with the CQL that caused it' do
            begin
              client.execute('SELECT * FROM things').value
            rescue QueryError => e
              e.cql.should == 'SELECT * FROM things'
            else
              fail('No error was raised')
            end
          end
        end

        context 'with a timeout' do
          it 'passes the timeout along with the request' do
            sent_timeout = nil
            handle_request do |request, _, _, timeout|
              sent_timeout = timeout
              nil
            end
            client.execute(cql, timeout: 3).value
            sent_timeout.should == 3
          end
        end

        context 'with tracing' do
          it 'sets the trace flag' do
            tracing = false
            handle_request do |request|
              if request.is_a?(Protocol::QueryRequest)
                tracing = request.trace
              end
            end
            client.execute(cql, trace: true).value
            tracing.should be_true
          end

          it 'returns the trace ID with the result' do
            trace_id = Uuid.new('a1028490-3f05-11e3-9531-fb72eff05fbb')
            handle_request do |request|
              if request.is_a?(Protocol::QueryRequest) && request.cql == cql
                Protocol::RowsResultResponse.new([], [], trace_id)
              end
            end
            result = client.execute(cql, trace: true).value
            result.trace_id.should == trace_id
          end
        end
      end

      describe '#prepare' do
        let :id do
          'A' * 32
        end

        let :metadata do
          [['stuff', 'things', 'item', :varchar]]
        end

        let :cql do
          'SELECT * FROM stuff.things WHERE item = ?'
        end

        before do
          handle_request do |request|
            if request.is_a?(Protocol::PrepareRequest)
              Protocol::PreparedResultResponse.new(id, metadata, nil)
            end
          end
        end

        before do
          client.connect.value
        end

        it 'sends a prepare request' do
          client.prepare('SELECT * FROM system.peers').value
          last_request.should == Protocol::PrepareRequest.new('SELECT * FROM system.peers')
        end

        it 'returns a prepared statement' do
          statement = client.prepare(cql).value
          statement.should_not be_nil
        end

        it 'executes a prepared statement using the default consistency level' do
          statement = client.prepare(cql).value
          statement.execute('foo').value
          last_request.should == Protocol::ExecuteRequest.new(id, metadata, ['foo'], :quorum)
        end

        it 'executes a prepared statement using the consistency specified when the client was created' do
          client = described_class.new(connection_options.merge(default_consistency: :all))
          client.connect.value
          statement = client.prepare(cql).value
          statement.execute('foo').value
          last_request.should == Protocol::ExecuteRequest.new(id, metadata, ['foo'], :all)
        end

        it 'returns a prepared statement that knows the metadata' do
          statement = client.prepare(cql).value
          statement.metadata['item'].type == :varchar
        end

        it 'executes a prepared statement with a specific consistency level' do
          statement = client.prepare(cql).value
          statement.execute('thing', :local_quorum).value
          last_request.should == Protocol::ExecuteRequest.new(id, metadata, ['thing'], :local_quorum)
        end

        context 'when there is an error creating the request' do
          it 'returns a failed future' do
            f = client.prepare(nil)
            expect { f.value }.to raise_error(ArgumentError)
          end
        end

        context 'when there is an error preparing the request' do
          it 'returns a failed future' do
            handle_request do |request|
              if request.is_a?(Protocol::PrepareRequest)
                Protocol::PreparedResultResponse.new(id, metadata, nil)
              end
            end
            statement = client.prepare(cql).value
            f = statement.execute
            expect { f.value }.to raise_error(ArgumentError)
          end
        end

        context 'with multiple connections' do
          let :connection_options do
            {:hosts => %w[host1 host2], :port => 12321, :io_reactor => io_reactor, :logger => logger}
          end

          it 'prepares the statement on all connections' do
            statement = client.prepare('SELECT * FROM stuff WHERE item = ?').value
            started_at = Time.now
            until connections.map { |c| c.requests.last }.all? { |r| r.is_a?(Protocol::ExecuteRequest) }
              statement.execute('hello').value
              raise 'Did not receive EXECUTE requests on all connections within 5s' if (Time.now - started_at) > 5
            end
            connections.map { |c| c.requests.last }.should == [
              Protocol::ExecuteRequest.new(id, metadata, ['hello'], :quorum),
              Protocol::ExecuteRequest.new(id, metadata, ['hello'], :quorum),
            ]
          end
        end
      end

      context 'when not connected' do
        it 'is not connected before #connect has been called' do
          client.should_not be_connected
        end

        it 'is not connected after #close has been called' do
          client.connect.value
          client.close.value
          client.should_not be_connected
        end

        it 'complains when #use is called before #connect' do
          expect { client.use('system').value }.to raise_error(NotConnectedError)
        end

        it 'complains when #use is called after #close' do
          client.connect.value
          client.close.value
          expect { client.use('system').value }.to raise_error(NotConnectedError)
        end

        it 'complains when #execute is called before #connect' do
          expect { client.execute('DELETE FROM stuff WHERE id = 3').value }.to raise_error(NotConnectedError)
        end

        it 'complains when #execute is called after #close' do
          client.connect.value
          client.close.value
          expect { client.execute('DELETE FROM stuff WHERE id = 3').value }.to raise_error(NotConnectedError)
        end

        it 'complains when #prepare is called before #connect' do
          expect { client.prepare('DELETE FROM stuff WHERE id = 3').value }.to raise_error(NotConnectedError)
        end

        it 'complains when #prepare is called after #close' do
          client.connect.value
          client.close.value
          expect { client.prepare('DELETE FROM stuff WHERE id = 3').value }.to raise_error(NotConnectedError)
        end

        it 'complains when #execute of a prepared statement is called after #close' do
          handle_request do |request|
            if request.is_a?(Protocol::PrepareRequest)
              Protocol::PreparedResultResponse.new('A' * 32, [], nil)
            end
          end
          client.connect.value
          statement = client.prepare('DELETE FROM stuff WHERE id = 3').value
          client.close.value
          expect { statement.execute.value }.to raise_error(NotConnectedError)
        end
      end

      context 'when nodes go down' do
        include_context 'peer discovery setup'

        let :connection_options do
          {:hosts => %w[host1 host2 host3], :port => 12321, :io_reactor => io_reactor}
        end

        before do
          client.connect.value
        end

        it 'clears out old connections and don\'t reuse them for future requests' do
          connections.first.close
          expect { 10.times { client.execute('SELECT * FROM something').value } }.to_not raise_error
        end

        it 'raises NotConnectedError when all nodes are down' do
          connections.each(&:close)
          expect { client.execute('SELECT * FROM something').value }.to raise_error(NotConnectedError)
        end

        it 'reconnects when it receives a status change UP event' do
          connections.first.close
          event = Protocol::StatusChangeEventResponse.new('UP', IPAddr.new('1.1.1.1'), 9999)
          connections.select(&:has_event_listener?).first.trigger_event(event)
          connections.select(&:connected?).should have(3).items
        end

        it 'eventually reconnects even when the node doesn\'t respond at first' do
          timer_promise = Promise.new
          io_reactor.stub(:schedule_timer).and_return(timer_promise.future)
          additional_nodes.each { |host| io_reactor.node_down(host.to_s) }
          connections.first.close
          event = Protocol::StatusChangeEventResponse.new('UP', IPAddr.new('1.1.1.1'), 9999)
          connections.select(&:has_event_listener?).first.trigger_event(event)
          connections.select(&:connected?).should have(2).items
          additional_nodes.each { |host| io_reactor.node_up(host.to_s) }
          timer_promise.fulfill
          connections.select(&:connected?).should have(3).items
        end

        it 'connects when it receives a topology change UP event' do
          min_peers[0] = 3
          event = Protocol::TopologyChangeEventResponse.new('UP', IPAddr.new('1.1.1.1'), 9999)
          connections.select(&:has_event_listener?).first.trigger_event(event)
          connections.select(&:connected?).should have(4).items
        end

        it 'registers a new event listener when the current event listening connection closes' do
          connections.select(&:has_event_listener?).should have(1).item
          connections.select(&:has_event_listener?).first.close
          connections.select(&:connected?).select(&:has_event_listener?).should have(1).item
        end
      end

      context 'with logging' do
        include_context 'peer discovery setup'

        it 'logs when connecting to a node' do
          logger.stub(:debug)
          client.connect.value
          logger.should have_received(:debug).with(/Connecting to node at example\.com:12321/)
        end

        it 'logs when a node is connected' do
          logger.stub(:info)
          client.connect.value
          logger.should have_received(:info).with(/Connected to node .{36} at example\.com:12321 in data center dc1/)
        end

        it 'logs when all nodes are connected' do
          logger.stub(:info)
          client.connect.value
          logger.should have_received(:info).with(/Cluster connection complete/)
        end

        it 'logs when the connection fails' do
          logger.stub(:error)
          io_reactor.stub(:connect).and_return(Future.failed(StandardError.new('Hurgh blurgh')))
          client.connect.value rescue nil
          logger.should have_received(:error).with(/Failed connecting to cluster: Hurgh blurgh/)
        end

        it 'logs when a single connection fails' do
          logger.stub(:warn)
          io_reactor.stub(:connect).and_return(Future.failed(StandardError.new('Hurgh blurgh')))
          client.connect.value rescue nil
          logger.should have_received(:warn).with(/Failed connecting to node at example\.com:12321: Hurgh blurgh/)
        end

        it 'logs when a connection fails' do
          logger.stub(:warn)
          client.connect.value
          connections.sample.close
          logger.should have_received(:warn).with(/Connection to node .{36} at .+:\d+ in data center .+ unexpectedly closed/)
        end

        it 'logs when it does a peer discovery' do
          logger.stub(:debug)
          client.connect.value
          logger.should have_received(:debug).with(/Looking for additional nodes/)
          logger.should have_received(:debug).with(/\d+ additional nodes found/)
        end

        it 'logs when it receives an UP event' do
          logger.stub(:debug)
          client.connect.value
          event = Protocol::StatusChangeEventResponse.new('UP', IPAddr.new('1.1.1.1'), 9999)
          connections.select(&:has_event_listener?).first.trigger_event(event)
          logger.should have_received(:debug).with(/Received UP event/)
        end

        it 'logs when it fails with a connect after an UP event' do
          logger.stub(:debug)
          logger.stub(:warn)
          additional_nodes.each { |host| io_reactor.node_down(host.to_s) }
          client.connect.value
          event = Protocol::StatusChangeEventResponse.new('UP', IPAddr.new('1.1.1.1'), 9999)
          connections.select(&:has_event_listener?).first.trigger_event(event)
          logger.should have_received(:warn).with(/Failed connecting to node/).at_least(1).times
          logger.should have_received(:debug).with(/Scheduling new peer discovery in \d+s/)
        end

        it 'logs when it disconnects' do
          logger.stub(:info)
          client.connect.value
          client.close.value
          logger.should have_received(:info).with(/Cluster disconnect complete/)
        end

        it 'logs when it fails to disconnect' do
          logger.stub(:error)
          client.connect.value
          io_reactor.stub(:stop).and_return(Future.failed(StandardError.new('Hurgh blurgh')))
          client.close.value rescue nil
          logger.should have_received(:error).with(/Cluster disconnect failed: Hurgh blurgh/)
        end
      end
    end
  end
end
