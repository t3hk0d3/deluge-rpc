require 'rencoder'
require 'socket'
require 'openssl'
require 'thread'
require 'zlib'
require 'stringio'

require 'concurrent'

module Deluge
  module Api
    class Connection
      class RPCError < StandardError; end

      class InvokeTimeoutError < StandardError; end

      DEFAULT_CALL_TIMEOUT = 1 # second

      RPC_RESPONSE = 1
      RPC_ERROR = 2
      RPC_EVENT = 3

      attr_reader :host, :port
      attr_reader :username, :password

      def initialize(options = {})
        @host = options.delete(:host) || 'localhost'
        @port = (options.delete(:port) || 58846).to_i

        @call_timeout = options.delete(:call_timeout) || 5.0 # 5 seconds timeout

        @request_id = Concurrent::AtomicFixnum.new
        @running = Concurrent::AtomicBoolean.new

        @messages = {}

        @write_mutex = Mutex.new
      end

      def start
        raise 'Connection already opened' if @connection

        @connection = OpenSSL::SSL::SSLSocket.new(create_socket, ssl_context)

        @connection.connect

        @running.make_true

        @main_thread = Thread.current
        @thread = Thread.new(&self.method(:read_loop))
      end

      def close
        @running.make_false
      end

      def call(method, *args)
        kwargs = {}
        kwargs = args.pop if args.size == 1 && args.last.is_a?(Hash)

        future = Concurrent::IVar.new

        request_id = @request_id.increment
        message = [[request_id, method, args, kwargs]]

        raw = Zlib::Deflate.deflate Rencoder.dump(message)

        @write_mutex.synchronize do
          @messages[request_id] = future

          if IO.select([], [@connection], nil, nil)
            @connection.write(raw)
          end
        end

        result = future.value!(@call_timeout)

        if result.nil? && future.pending?
          raise InvokeTimeoutError.new("Failed to retreive response for '#{method}' in #{@call_timeout} seconds. Probably method not exists.")
        end

        result
      end

      private

      def read_loop
        while(@running.true?)
          next unless IO.select([@connection], nil, nil, 0.1)

          raw = ""
          begin
            buffer = @connection.readpartial(1024)
            raw += buffer
          end until(buffer.size < 1024)

          raw = Zlib::Inflate.inflate(raw)

          parse_packets(raw).each do |packet|
            type, response_id, value = packet

            var = @messages[response_id]

            next unless var # TODO: Handle unknown messages

            case type
            when RPC_RESPONSE
              var.set(value)
            when RPC_ERROR
              var.fail(RPCError.new(value))
            # TODO: Add events support
            else
              raise "Unknown response type #{type}"
            end
          end
        end

        @connection.close if @connection
        @connection = nil
      rescue => e
        @main_thread.raise(e)
      end

      def create_socket
        socket = TCPSocket.new(host, port)

        if ::Socket.constants.include?('TCP_NODELAY') || ::Socket.constants.include?(:TCP_NODELAY)
          socket.setsockopt(::Socket::IPPROTO_TCP, ::Socket::TCP_NODELAY, true)
        end
        socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_KEEPALIVE, true)

        socket
      end

      def ssl_context
        # SSLv3 is not allowed (http://dev.deluge-torrent.org/ticket/2555)
        context = OpenSSL::SSL::SSLContext.new('SSLv23')
        # TODO: Consider allowing server certificate validation
        context.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE)

        context
      end

      def parse_packets(raw)
        io = StringIO.new(raw)

        packets = []

        until(io.eof?)
          packets << Rencoder.load(io)
        end

        packets
      end
    end
  end
end
