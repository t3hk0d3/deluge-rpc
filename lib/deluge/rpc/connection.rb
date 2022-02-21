# frozen_string_literal: true

require 'rencoder'

require 'socket'
require 'openssl'
require 'thread'
require 'zlib'
require 'stringio'

require 'concurrent'

module Deluge
  module Rpc
    class Connection
      class RPCError < StandardError; end
      class InvokeTimeoutError < StandardError; end
      class ConnectionClosedError < StandardError; end

      PROTOCOL_VERSION = 0x01

      DAEMON_LOGIN = 'daemon.login'
      DAEMON_METHOD_LIST = 'daemon.get_method_list'
      DAEMON_REGISTER_EVENT = 'daemon.set_event_interest'

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
        @events = {}

        @write_mutex = Mutex.new
      end

      def start
        raise 'Connection already opened' if @connection

        @connection = OpenSSL::SSL::SSLSocket.new(create_socket, ssl_context)

        @connection.connect

        @running.make_true

        @main_thread = Thread.current
        @thread = Thread.new(&self.method(:read_loop))

        # register present events
        recover_events! if @events.size > 0

        true
      end

      def authenticate(login, password)
        self.call(DAEMON_LOGIN, login, password)
      end

      def method_list
        self.call(DAEMON_METHOD_LIST)
      end

      def register_event(event_name, force = false, &block)
        unless @events[event_name] # Register event only ONCE!
          self.call(DAEMON_REGISTER_EVENT, [event_name]) if @connection # Let events be initialized lazily
        end

        @events[event_name] ||= []
        @events[event_name] << block

        true
      end

      def close
        @running.make_false
      end

      def call(method, *args)
        raise "Not connected!" unless @connection

        kwargs = {}
        kwargs = args.pop if args.size == 1 && args.last.is_a?(Hash)
        kwargs['client_version'] = Deluge::Rpc::VERSION.to_s if method == 'daemon.login'

        future = Concurrent::IVar.new

        request_id = @request_id.increment
        @messages[request_id] = future

        message = [[request_id, method, args, kwargs]]

        write_packet(message)

        result = future.value!(@call_timeout)

        if result.nil? && future.pending?
          raise InvokeTimeoutError.new("Failed to retrieve response for '#{method}' in #{@call_timeout} seconds. Probably method not exists.")
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
      rescue => e
        @main_thread.raise(e)
      ensure
        @connection.close if @connection
        @connection = nil
        @messages.clear
      end

      def dispatch_packet(packet)
        type, response_id, value = packet

        case type
        when RPC_RESPONSE, RPC_ERROR
          future = @messages.delete(response_id)

          return unless future # TODO: Handle unknown messages

          if type == RPC_RESPONSE
            future.set(value)
          else
            future.fail(RPCError.new(value))
          end
        when RPC_EVENT
          handlers = @events[response_id]
          return unless handlers # TODO: Handle unknown events

          handlers.each do |block|
            block.call(*value)
          end
        else
          raise "Unknown packet type #{type.inspect}"
        end
      end

      def write_packet(packet)
        raw = Zlib::Deflate.deflate Rencoder.dump(packet)
        raw = [PROTOCOL_VERSION, raw.bytesize].pack("CN") + raw

        @write_mutex.synchronize do
          if IO.select([], [@connection], nil, nil)
            @connection.write(raw)
          end
        end
      end

      def read_packets(socket)
        raw = ""

        # Read message header
        protocol_version, buffer_size = socket.readpartial(5).unpack('CN')

        raise('Received response with unknown protocol_version=' + protocol_version) if protocol_version != PROTOCOL_VERSION

        raw = socket.readpartial(buffer_size)
        raw = Zlib::Inflate.inflate(raw)

        parse_packets(raw)
      end

      def recover_events!
        present_events = @events
        @events = {}

        present_events.each do |event, handlers|
          handlers.each do |handler|
            self.register_event(event, &handler)
          end
        end
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
        OpenSSL::SSL::SSLContext.new
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
