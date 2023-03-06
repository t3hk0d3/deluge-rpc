# frozen_string_literal: true

module Deluge
  module Rpc
    class Namespace
      attr_reader :name, :connection, :namespaces, :api_methods

      def initialize(name, connection)
        @name = name
        @connection = connection
        @namespaces = {}
        @api_methods = []
      end

      def register_namespace(namespace)
        namespace = namespace.to_sym

        return namespaces[namespace] if namespaces.include?(namespace)

        ns = Namespace.new("#{name}.#{namespace}", connection)

        namespaces[namespace] = ns

        define_singleton_method(namespace) do
          ns
        end

        ns
      end

      def register_method(method)
        method = method.to_sym

        api_methods << "#{name}.#{method}"

        define_singleton_method(method) do |*args|
          call(method, *args)
        end
      end

      def call(method, *args)
        method_name = "#{name}.#{method}"

        @connection.call(method_name, *args)
      end
    end
  end
end
