require 'spec_helper'

describe Deluge::Api::Namespace do

  let(:connection) do
    double('ApiConnection').tap do |connection|
      allow(connection).to receive(:call)
    end
  end

  let(:instance) { described_class.new('root', connection) }

  describe '#register_namespace' do
    let(:result) { instance.register_namespace('test') }

    it 'register new namespace' do
      expect(result).to eq(instance.namespaces[:test])
    end

    it 'returns registered namespace' do
      expect(result).to be_a(described_class).and have_attributes(name: 'root.test')
    end

    it 'returns existing namespace if its already registered' do
      expect(instance.register_namespace('test')).to eql(result)
    end

    it 'creates namespace access instance method' do
      expect(result).to eq(instance.test)
    end
  end

  describe '#register_method' do
    before do
      instance.register_method('test')
    end

    it 'register new api method' do
      expect(instance.api_methods).to include('root.test')
    end

    it 'create instance method' do
      expect(instance).to respond_to(:test)
    end
  end

  describe 'api access instance method' do
    before do
      instance.register_method('test')

      instance.test('hello', 'world')
    end

    it 'invoke api call' do
      expect(connection).to have_received(:call).with('root.test', 'hello', 'world')
    end
  end

end