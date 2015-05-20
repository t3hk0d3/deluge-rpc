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
      class ConnectionClosedError < StandardError; end

      DAEMON_LOGIN = 'daemon.login'
      DAEMON_METHOD_LIST = 'daemon.get_method_list'

      DEFAULT_CALL_TIMEOUT = 5.0 # seconds

      DEFAULT_PORT = 58846

      RPC_RESPONSE = 1
      RPC_ERROR = 2
      RPC_EVENT = 3

      attr_reader :host, :port

      def initialize(options = {})
        @host = options.delete(:host) || 'localhost'
        @port = (options.delete(:port) || DEFAULT_PORT).to_i

        @call_timeout = options.delete(:call_timeout) || DEFAULT_CALL_TIMEOUT

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

      def authenticate(login, password)
        self.call(DAEMON_LOGIN, login, password)
      end

      def method_list
        self.call(DAEMON_METHOD_LIST)
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
          io_poll = IO.select([@connection], nil, [@connection], 0.1)

          next unless io_poll

          read_sockets, _, error_sockets = io_poll

          if @connection.eof?
            # TODO: implement auto-recovery
            raise ConnectionClosedError
          end

          read_sockets.each do |socket|
            packets = read_packets(socket)

            packets.each do |packet|
              dispatch_packet(packet)
            end
          end
        end

        @connection.close if @connection
        @connection = nil
      rescue => e
        @main_thread.raise(e)
      end

      def dispatch_packet(packet)
        type, response_id, value = packet

        var = @messages[response_id]

        return unless var # TODO: Handle unknown messages

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

      def read_packets(socket)
        raw = ""
        begin
          buffer = socket.readpartial(1024)
          raw += buffer
        end until(buffer.size < 1024)

        raw = Zlib::Inflate.inflate(raw)

        parse_packets(raw)
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
