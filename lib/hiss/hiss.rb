#!/usr/bin/ruby --
# for-fun implementation of Shamir's Secret Sharing
# https://en.wikipedia.org/wiki/Shamir%27s_Secret_Sharing

require 'prime'

module Hiss
  class Hiss
    def initialize(secret, totalNumberOfPieces, requiredPiecesToDecode)
      @secret = secret
      @piecesCount = totalNumberOfPieces
      @requiredPiecesCount = requiredPiecesToDecode
      # FIXME: Don't just take the next largest prime
      @prime = Prime.detect{ |n| n > secret }
    end

    # Generate (requiredPiecesCount - 1) polynomial coefficients less than prime
    def self.generate_coefficients(requiredPiecesCount, prime)
      (1..(requiredPiecesCount - 1)).collect do
        Random.rand(prime).to_i
      end
    end

    # Generate the first piecesCount points on the polynomial described by coefficients
    # (coefficients[0] * (x ** 0)) + ...
    def self.generate_points(secret, piecesCount, coefficients, prime)
      pieces = (0..piecesCount).collect {|x|
        sum = secret
        coefficients.each_with_index { |coefficient, index|
          sum += coefficient * (x ** (index + 1))
        }
        [x, sum % prime]
      }
      return pieces.drop(1), prime
    end

    def generate
      Hiss.generate_points(@secret, @piecesCount, Hiss.generate_coefficients(@requiredPiecesCount, @prime), @prime)
    end

    def self.modular_multiplicative_inverse(a, z)
      # https://en.wikipedia.org/wiki/Extended_Euclidean_algorithm
      x = 0
      last_x = 1
      y = 1
      last_y = 0

      while z != 0
        integer_quotient = a.div(z)
        a, z = z, a % z
        last_x, x = x, last_x - (integer_quotient * x)
        last_y, y = y, last_y - (integer_quotient * y)
      end
      return last_x, last_y
    end

    def self.divide_and_apply_modulus(numerator, denominator, prime)
      inverse_denominator, _ = modular_multiplicative_inverse(denominator, prime)
      return numerator * inverse_denominator
    end

    def self.multiply_all(numbers)
      numbers.inject(1){ |total, number| total * number }
    end

    # Solve for the 0th-order term of the lagrange polynomial partially described by points
    # in the prime finite field for prime
    def self.interpolate_secret(points, prime)
      x_values = points.collect{ |point| point[0] }
      y_values = points.collect{ |point| point[1] }
      numerators = []
      denominators = []
      x_values.each_index do |index|
        other_x_values = x_values.clone()
        this_x = other_x_values.slice!(index)
        numerators << multiply_all(other_x_values.collect{ |x| 0 - x })
        denominators << multiply_all(other_x_values.collect{ |x| this_x - x })
      end

      denominator = multiply_all(denominators)

      numerator = 0
      x_values.each_index do |index|
        numerator += divide_and_apply_modulus(numerators[index] * denominator * y_values[index] % prime, denominators[index], prime)
      end
      return (divide_and_apply_modulus(numerator, denominator, prime) + prime) % prime
    end
  end
end
