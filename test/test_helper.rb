ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/bingo_helpers"

class ActiveSupport::TestCase
  include BingoHelpers
  parallelize(workers: 1)
end
