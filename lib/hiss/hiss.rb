# for-fun implementation of Shamir's Secret Sharing
# https://en.wikipedia.org/wiki/Shamir%27s_Secret_Sharing

require 'prime'

module Hiss
  PACK_FORMAT = 'C*' # input is a byte stream
  PIECE_PACK_FORMAT = 'n*' # output values are integers in 0 <= n < @prime

  class Hiss
    BUFFER_SIZE = 8192

    def initialize(secret, totalNumberOfPieces, requiredPiecesToDecode)
      @secret = secret
      @piecesCount = totalNumberOfPieces
      @requiredPiecesCount = requiredPiecesToDecode
      @prime = 7919 # Chosen by random dice roll ;-)
    end

    # Return @piecesCount [pieceIndex, string] pairs and @prime
    def generate
      return Hiss.generate_string(@secret, @piecesCount, @requiredPiecesCount, @prime) { |progress|
        yield progress if block_given?
      }, @prime
    end

    # Generate (requiredPiecesCount - 1) polynomial coefficients less than prime
    def self.generate_coefficients(requiredPiecesCount, prime)
      (2..requiredPiecesCount).collect do
        Random.rand(prime).to_i
      end
    end

    # Process a secret file and generate an output file per piece
    # Format:
    # pieceIndex\n (text)
    # prime\n      (text)
    # raw binary data
    def self.generate_file(secretFile, totalPieces, requiredPieces, prime)
      pieceNames = nil
      pieceFiles = nil
      secretFilePath = Pathname.new(secretFile)
      chunks = secretFilePath.basename.to_s().split(/\./)
      basename = if chunks.length == 1
                   chunks[0]
                 else
                   chunks.slice!(-1)
                   chunks.join('.')
                 end
      parent = secretFilePath.parent

      begin
        pieceNames = (1..totalPieces).collect do |index|
          parent.join("#{basename}-#{index}.shard").to_s()
        end
        pieceFiles = pieceNames.collect { |file| File.open(file, 'wb')}
        totalProgress = 0

        File.open(secretFile, 'rb') do |secretStream|
          firstChunk = true
          buffer = ''

          while secretStream.read(BUFFER_SIZE, buffer)
            Hiss.generate_string(buffer, totalPieces, requiredPieces, prime){ |progress|
              yield totalProgress + progress if block_given?
            }.each_with_index do |generatedBuffer, index|
              outputStream = pieceFiles[index]
              if firstChunk
                outputStream.write("#{generatedBuffer[0].to_s()}\n") # index
                outputStream.write("#{prime.to_s()}\n")              # prime
              end
              outputStream.write(generatedBuffer[1])                 # raw data
            end
            firstChunk = false
            totalProgress += buffer.length
          end
        end
      ensure
        pieceFiles.each { |file| file.close() } if pieceFiles
      end

      return pieceNames
    end

    # Generate the first piecesCount values for the polynomial for each byte in secret, and pack them into a string
    def self.generate_string(secret, piecesCount, requiredPiecesCount, prime)
      generate_buffer(secret.unpack(PACK_FORMAT), piecesCount, requiredPiecesCount, prime) { |progress|
        yield progress if block_given?
      }.collect do |buffer|
        [buffer[0], buffer[1].pack(PIECE_PACK_FORMAT)]
      end
    end

    # Generate the first piecesCount values for the polynomial for each byte in secret
    def self.generate_buffer(secret, piecesCount, requiredPiecesCount, prime)
      pointBuffers = (1..piecesCount).collect{ |index| [index, []] }
      secret.each_with_index do |byte, byteIndex|
        generate_points(byte, piecesCount, generate_coefficients(requiredPiecesCount, prime), prime).each { |point|
          pointBuffers[point[0] - 1][1] << point[1]
        }
        yield byteIndex if block_given?
      end
      return pointBuffers
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
      return pieces.drop(1)
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

    def self.read_headers(pieces)
      indices = []
      primes = []
      buffers = []
      pieces.each do |piece|
        header = piece.read(BUFFER_SIZE).split("\n", 3)
        indices << header[0].strip().to_i()
        primes << header[1].strip().to_i()
        trailing_buffer = piece.read(BUFFER_SIZE - header[2].length)
        header[2] += trailing_buffer if trailing_buffer
        buffers << header[2]
      end

      validate_header(indices, primes, buffers)

      return indices, primes, buffers
    end

    def self.validate_header(indices, primes, buffers)
      if indices.uniq() != indices
        raise "Duplicate indices #{indices - indices.uniq()} in input files"
      end
      if primes.uniq().length != 1
        raise "Input files have differing prime modulators #{primes.uniq()}"
      end
      #TODO: Anything for buffers?
    end

    def self.validate_piece_files(filenames)
      sizes = filenames.collect{ |file| Pathname.new(file).size }.uniq()
      raise "Mismatching file sizes #{sizes}" if sizes.length > 1
    end

    # Solve for each value encoded in a set of files and write a file built from the solution
    # See generate_file for format
    def self.interpolate_file(pieceFiles, destinationFile)
      File.open(destinationFile, 'wb') do |destination|
        pieces = pieceFiles.collect{ |file| File.open(file, 'rb') }
        begin
          indices, primes, buffers = read_headers(pieces)
          totalProgress = 0

          while buffers.all?{ |buffer| buffer }
            points = (1..buffers.length).collect{ |index| [indices[index - 1], buffers[index - 1]]}
            destination.write(interpolate_string(points, primes[0]){ |progress|
              yield totalProgress + progress if block_given?
            })
            totalProgress += buffers[0].length
            pieces.each_index{ |index| buffers[index] = pieces[index].read(BUFFER_SIZE, buffers[index]) }
          end
        ensure
          pieces.each{ |file| file.close() }
        end
      end
    end

    # Solve for each value encoded in strings and return a string built from the solutions
    def self.interpolate_string(strings, prime)
      pointBuffers = strings.collect do |string|
        [string[0], string[1].unpack(PIECE_PACK_FORMAT)]
      end
      return interpolate_buffer(pointBuffers, prime){ |progress|
        yield progress if block_given?
      }.pack(PACK_FORMAT)
    end

    def self.validate_buffers(buffers)
      raise "Malformed buffer input #{buffers}" if buffers.any?{ |buffer| buffer.length != 2 }
      lengths = buffers.collect{ |buffer| buffer[1].length }.uniq()
      raise "Differing buffer lengths #{lengths}" if lengths.length > 1
    end

    # Solve for each set of points in points and return an ordered array of solutions
    def self.interpolate_buffer(points, prime)
      validate_buffers(points)
      pointCount = points[0][1].length
      (1..pointCount).collect do |index|
        yield index - 1 if block_given?
        interpolate_secret(points.collect{ |point| [point[0], point[1][index - 1]]}, prime)
      end
    end

    def self.validate_points(points, prime)
      raise "Insufficient number of inputs (#{points.length})" if points.length < 3
      raise "Prime #{prime} must be greater than all values #{points}}" if points.any?{ |point| point[1] >= prime }
    end

    # Solve for the 0th-order term of the lagrange polynomial partially described by points
    # in the prime finite field for prime
    def self.interpolate_secret(points, prime)
      validate_points(points, prime)
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
