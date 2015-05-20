require 'spec_helper'

describe Deluge::Api::Client do

  let(:connection) do
    double('ApiConnection').tap do |connection|
      allow(connection).to receive(:start)
      allow(connection).to receive(:authenticate).with('test', 'password').and_return(5)
      allow(connection).to receive(:method_list).and_return(['test.api.method'])
      allow(connection).to receive(:call).with('test.api.method').and_return('winning')
      allow(connection).to receive(:close)
    end
  end

  before do
    allow(Deluge::Api::Connection).to receive(:new).with(kind_of(Hash)).and_return(connection)
  end

  subject { described_class.new(host: 'localhost', login: 'test', password: 'password') }

  describe '#connect' do
    before do
      subject.connect
    end

    it 'starts connection' do
      expect(connection).to have_received(:start)
    end

    it 'authenticate' do
      expect(connection).to have_received(:authenticate).with('test', 'password')
    end

    it 'set auth_level' do
      expect(subject.auth_level).to eq(5)
    end

    it 'register methods' do
      expect(subject.api_methods).to include('test.api.method')
    end

    it 'create namespace access methods' do
      expect(subject.test).to be_a(Deluge::Api::Namespace).and have_attributes(name: 'test')
    end

    it 'create api access methods' do
      expect(subject.test.api.method).to eq('winning')
    end
  end

  describe '#close' do
    before do
      subject.connect

      subject.close
    end

    it 'closes connection' do
      expect(connection).to have_received(:close)
    end

    it 'clear namespaces' do
      expect(subject.namespaces).to be_empty
    end

    it 'clear methods' do
      expect(subject.api_methods).to be_empty
    end

    it 'remove namespace methods' do
      expect(subject).not_to respond_to(:test)
    end
  end
end
