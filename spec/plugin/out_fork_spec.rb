require 'spec_helper'

describe Fluent::ForkOutput do
  let(:tag) { "test.fork" }
  let(:required_params) { {output_tag: 'ot', output_key: 'ok', fork_key: 'sk'} }
  let(:params) { required_params }
  let(:config) { params.map{ |k, v| "#{k} #{v}" }.join("\n") }
  subject { Fluent::Test::OutputTestDriver.new(Fluent::ForkOutput, tag).configure(config) }

  describe "#configure" do
    let(:params) { required_params.merge(separator: '-', max_size: 5, max_fallback: 'drop', no_unique: true) }
    it "does not raise any error" do
      expect{ subject }.not_to raise_error
      expect(subject.instance.output_tag).to eq('ot')
      expect(subject.instance.output_key).to eq('ok')
      expect(subject.instance.fork_key).to eq('sk')
      expect(subject.instance.separator).to eq('-')
      expect(subject.instance.no_unique).to eq(true)
      expect(subject.instance.max_size).to eq(5)
      expect(subject.instance.max_fallback).to eq('drop')
    end
    context "without optional params" do
      let(:params) { required_params }
      it "use default values" do
        expect{ subject }.not_to raise_error
        expect(subject.instance.output_tag).to eq('ot')
        expect(subject.instance.output_key).to eq('ok')
        expect(subject.instance.fork_key).to eq('sk')
        expect(subject.instance.separator).to eq(',')
        expect(subject.instance.no_unique).to eq(false)
        expect(subject.instance.max_size).to eq(nil)
        expect(subject.instance.max_fallback).to eq('log')
      end
    end
    context "with invalid fallback" do
      let(:params) { required_params.merge(max_fallback: 'invalid') }
      it "raise an error" do
        expect{ subject }.to raise_error(Fluent::ConfigError)
      end
    end
    [:output_tag, :output_key, :fork_key].each do |rk|
      context "no #{rk}" do
        let(:params) { required_params.reject{ |k, v| k == rk } }
        it "raises Fluent::ConfigError" do
          expect{ subject }.to raise_error(Fluent::ConfigError)
        end
      end
    end
  end

  describe "#run" do
    let(:time) { Time.now.to_i }
    it "forks" do
      subject.run { subject.emit({"sk" => "2,3,4,5"}, time) }
      expect(subject.emits.size).to eq(4)
      expect(subject.emits).to include(["ot", time, {"ok" => "2"}])
      expect(subject.emits).to include(["ot", time, {"ok" => "3"}])
      expect(subject.emits).to include(["ot", time, {"ok" => "4"}])
      expect(subject.emits).to include(["ot", time, {"ok" => "5"}])
    end
    it "forks uniquely" do
      subject.run { subject.emit({"sk" => "2,3,4,3"}, time) }
      expect(subject.emits.size).to eq(3)
      expect(subject.emits).to include(["ot", time, {"ok" => "2"}])
      expect(subject.emits).to include(["ot", time, {"ok" => "3"}])
      expect(subject.emits).to include(["ot", time, {"ok" => "4"}])
    end
    it "forks with other params" do
      subject.run { subject.emit({"sk" => "2,3,4,5", "o1" => 1, "o2" => 2}, time) }
      expect(subject.emits.size).to eq(4)
      expect(subject.emits).to include(["ot", time, {"ok" => "2", "o1" => 1, "o2" => 2}])
      expect(subject.emits).to include(["ot", time, {"ok" => "3", "o1" => 1, "o2" => 2}])
      expect(subject.emits).to include(["ot", time, {"ok" => "4", "o1" => 1, "o2" => 2}])
      expect(subject.emits).to include(["ot", time, {"ok" => "5", "o1" => 1, "o2" => 2}])
    end
    it "does nothing for empty value" do
      subject.run { subject.emit({"o1" => 1, "o2" => 2}, time) }
      expect(subject.emits.size).to eq(0)
    end
    it "ignores exceptions and writes down the log" do
      expect(subject.instance.log).to receive(:error).with(/^The error/)
      allow_any_instance_of(String).to receive(:split).and_raise("The error")
      subject.emit({"sk" => "2,3,4,5", "o1" => 1, "o2" => 2}, time)
    end
    context "with no_unique option" do
      let(:params) { required_params.merge(no_unique: true) }
      it "forks for redundant values" do
        subject.run { subject.emit({"sk" => "2,3,4,3"}, time) }
        expect(subject.emits.size).to eq(4)
        expect(subject.emits).to include(["ot", time, {"ok" => "2"}])
        expect(subject.emits).to include(["ot", time, {"ok" => "3"}])
        expect(subject.emits).to include(["ot", time, {"ok" => "4"}])
        expect(subject.emits).to include(["ot", time, {"ok" => "3"}])
      end
    end
    context "with separator option" do
      let(:params) { required_params.merge(separator: '-') }
      it "forks by separating with '-'" do
        subject.run { subject.emit({"sk" => "2-3-4-5"}, time) }
        expect(subject.emits.size).to eq(4)
        expect(subject.emits).to include(["ot", time, {"ok" => "2"}])
        expect(subject.emits).to include(["ot", time, {"ok" => "3"}])
        expect(subject.emits).to include(["ot", time, {"ok" => "4"}])
        expect(subject.emits).to include(["ot", time, {"ok" => "5"}])
      end
    end
    context "with max_size and max_fallback options" do
      describe "log" do
        let(:params) { required_params.merge(max_size: 3, max_fallback: 'log') }
        it "writes a log" do
          expect(subject.instance.log).to receive(:info).with(/Too many forked values/)
          subject.run { subject.emit({"sk" => "2,3,4,5"}, time) }
        end
      end
      describe "drop" do
        let(:params) { required_params.merge(max_size: 3, max_fallback: 'drop') }
        it "drops exceeded values" do
          subject.run { subject.emit({"sk" => "2,3,4,5"}, time) }
          expect(subject.emits.size).to eq(3)
          expect(subject.emits).to include(["ot", time, {"ok" => "2"}])
          expect(subject.emits).to include(["ot", time, {"ok" => "3"}])
          expect(subject.emits).to include(["ot", time, {"ok" => "4"}])
        end
      end
    end
  end
end
