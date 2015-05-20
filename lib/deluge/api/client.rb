module Deluge
  module Api
    class Client
      attr_reader :namespaces, :api_methods, :auth_level

      def initialize(options = {})
        @connection = Deluge::Api::Connection.new(options)
        @login = options.fetch(:login)
        @password = options.fetch(:password)

        @namespaces = {}
        @api_methods = []
      end

      def connect
        @connection.start

        @auth_level = @connection.authenticate(@login, @password)

        register_methods!

        true
      end

      def register_event(event_name, &block)
        raise "Provide block for event" unless block

        if event_name.is_a?(Symbol)
          event_name = "#{event_name}_event"
          # convert to CamelCase
          event_name.gsub!(/(?:_|^)(.)/) { |match| $1.upcase }
        end

        @connection.register_event(event_name, &block)
      end

      def close
        @connection.close
        @auth_level = nil
        @api_methods = []
        @namespaces.each_key do |ns|
          self.singleton_class.send :undef_method, ns
        end
        @namespaces = {}
      end

      private

      def register_methods!
        methods = @connection.method_list

        methods.each do |method|
          *namespaces, method_name = method.split('.')

          register_method!(namespaces, method_name)
          @api_methods << method
        end
      end

      def register_method!(namespaces, method)
        namespace = register_namespace(namespaces)

        namespace.register_method(method)
      end

      def register_namespace(namespaces)
        ns = namespaces.shift

        root = @namespaces[ns]

        unless root
          root = Api::Namespace.new(ns, @connection)
          @namespaces[ns] = root

          define_singleton_method(ns.to_sym) do
            @namespaces[ns]
          end
        end

        namespaces.each do |namespace|
          root = root.register_namespace(namespace)
        end

        root
      end

    end
  end
end