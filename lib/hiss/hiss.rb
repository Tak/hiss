#!/usr/bin/ruby --
# for-fun implementation of Shamir's Secret Sharing

require 'prime'

module Hiss
  class Hiss
    def initialize(secret, totalNumberOfPieces, requiredPiecesToDecode)
      @secret = secret
      @piecesCount = totalNumberOfPieces
      @requiredPiecesCount = requiredPiecesToDecode
      @prime = Prime.take(Random.rand(1000) + 20).last
    end

    def self.generate_coefficients(secret, requiredPiecesCount, prime)
      coefficients = [secret]
      (1..(requiredPiecesCount - 1)).each do
        coefficients << Random.rand(prime).to_i
      end
      return coefficients
    end

    def self.generate_points(secret, piecesCount, coefficients, prime)
      pieces = (1..piecesCount).collect {|index|
        sum = 0
        coefficients.each_with_index { |coefficient, order|
          sum += coefficient * (index ** order)
        }
        [index, sum % prime]
      }
      return [0, secret] + pieces, prime
    end

    def generate
      Hiss.generate_points(@secret, @piecesCount, Hiss.generate_coefficients(@secret, @requiredPiecesCount, @prime), @prime)
    end

    def self.find_greatest_common_denominator(a, z)
      x = 0
      last_x = 1
      y = 1
      last_y = 0

      while z != 0
        integer_quotient = a.div(z)
        a, z = z, a % z
        x, last_x = last_x - (integer_quotient * x), x
        y, last_y = last_y - (integer_quotient * y), y
      end
      return last_x, last_y
    end

    def self.divide_and_apply_modulus(numerator, denominator, prime)
      inverse_denominator, _ = find_greatest_common_denominator(denominator, prime)
      return numerator * inverse_denominator
    end

    def self.multiply_all(numbers)
      numbers.inject(1){ |total, number| total * number }
    end

    def self.interpolate_secret(points, prime)
      puts("Interpolating from #{points} and #{prime}")
      x_coefficients = points.collect{ |point| point[0] }
      y_coefficients = points.collect{ |point| point[1] }
      numerators = []
      denominators = []
      x_coefficients.each_index do |index|
        other_x_coefficients = x_coefficients.clone()
        this_x = other_x_coefficients.slice!(index)
        numerators << multiply_all(other_x_coefficients.collect{ |x| 0 - x }) # Special-cased for 0
        denominators << multiply_all(other_x_coefficients.collect{ |x| this_x - x })
      end

      puts("numerators: #{numerators}")
      puts("denominators: #{denominators}")

      denominator = multiply_all(denominators)
      puts("denominator: #{denominator}")
      numerator = 0
      x_coefficients.each_index do |index|
        numerator += divide_and_apply_modulus(numerators[index] * denominator * y_coefficients[index] % prime, denominators[index], prime)
      end
      return (divide_and_apply_modulus(numerator, denominator, prime) + prime) % prime
    end
  end
end
