require 'rubygems'
require 'coveralls'
Coveralls.wear!

require 'fluent/test'
require 'fluent/test/driver/output'
require 'fluent/test/helpers'
require 'fluent/plugin/out_fork'

RSpec.configure do |config|
  config.before(:all) do
    Fluent::Test.setup
  end
end
