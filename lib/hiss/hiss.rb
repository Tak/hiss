#!/usr/bin/ruby --
# for-fun implementation of Shamir's Secret Sharing

require 'prime'

module Hiss
  class Hiss
    def initialize(secret, totalNumberOfPieces, requiredPiecesToDecode)
      # TODO: input
      @secret = secret
      @piecesCount = totalNumberOfPieces
      @requiredPiecesCount = requiredPiecesToDecode
      @prime = Prime.take(Random.rand(1000) + 20).last
    end

    def generate_coefficients
      @coefficients = [@secret]
      (0..@requiredPiecesCount).each do |index|
        @coefficients << Random.rand(@prime).to_i
      end
    end

    def generate_points
      generate_coefficients()
      @pieces = (0..@piecesCount).collect {|index|
        sum = 0
        @coefficients.each_with_index { |coefficient, order|
          sum += coefficient * ((index + 1) ** order)
        }
        [index, sum % @prime]
      }
    end
  end
end
