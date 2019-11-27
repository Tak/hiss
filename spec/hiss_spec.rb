require 'prime'

RSpec.describe Hiss do
  it "has a version number" do
    expect(Hiss::VERSION).not_to be nil
  end

  it "generates n-1 coefficients, all less than prime" do
    requiredPieces = 6
    prime = 1613
    coefficients = Hiss::Hiss.generate_coefficients(requiredPieces, prime)
    expect(coefficients.length).to eq(requiredPieces - 1)
    coefficients.each { |coefficient|
      expect(coefficient).to be <= prime
    }
  end

  it "creates a product of inputs" do
    testData = [
        [[], 1],
        [[1, 2, 3], 6],
        [[2, -1, 2], -4],
        [[0, -43, 112], 0]
    ]

    testData.each {|item|
      expect(Hiss::Hiss.multiply_all(item[0])).to eq(item[1])
    }
  end

  it "calculates modular multiplicative inverse given known inputs" do
    testData = [
        [[-4, 3617], 904],
        [[-4, 7211], -1803]
    ]
    testData.each {|item|
      inverse = Hiss::Hiss.modular_multiplicative_inverse(item[0][0], item[0][1])[0]
      expect(inverse).to eq(item[1])
      expect((item[0][0] * inverse) % item[0][1]).to eq(1) # roundtrip
    }
  end

  it "generates expected points given known inputs" do
    # https://en.wikipedia.org/wiki/Shamir%27s_Secret_Sharing
    secret = 1234
    numberOfPieces = 6
    coefficients = [166, 94]
    prime = 1613
    expected_y_values = [1494, 329, 965, 176, 1188, 775]

    pieces = Hiss::Hiss.generate_points(secret, numberOfPieces, coefficients, prime)

    expect(pieces.length).to eq(6)
    pieces.each_with_index { |piece, index|
      expect(piece[0]).to eq(index + 1)
      expect(piece[1]).to eq(expected_y_values[index])
    }
  end

  it "generates expected point buffer given known inputs" do
    # https://en.wikipedia.org/wiki/Shamir%27s_Secret_Sharing
    secret = '1234'.unpack(Hiss::PACK_FORMAT)
    numberOfPieces = 6
    requiredPieces = 3
    prime = 1613

    pieces = Hiss::Hiss.generate_buffer(secret, numberOfPieces, requiredPieces, prime)

    expect(pieces.length).to eq(numberOfPieces)
    calculatedSecret = Hiss::Hiss.interpolate_buffer(pieces, prime)
    expect(calculatedSecret).to eq(secret)
  end

  it "generates expected string given known inputs" do
    # https://en.wikipedia.org/wiki/Shamir%27s_Secret_Sharing
    secret = '1234'
    numberOfPieces = 6
    requiredPieces = 3
    prime = 1613

    pieces = Hiss::Hiss.generate_string(secret, numberOfPieces, requiredPieces, prime)

    expect(pieces.length).to eq(numberOfPieces)
    calculatedSecret = Hiss::Hiss.interpolate_string(pieces, prime)
    expect(calculatedSecret).to eq(secret)
  end

  def n_random_items_from(array, n)
    indices = (0..(array.length - 1)).collect().to_a()
    (1..n).collect do
      array[indices.slice!(Random.rand(indices.length))]
    end
  end

  it "successfully roundtrips a single random value" do
    secret = Random.rand(2 ** 16)
    numberOfPieces = 8
    requiredPiecesToDecode = 5
    prime = Prime::detect{ |n| n > secret }

    pieces = Hiss::Hiss.generate_points(secret, numberOfPieces, Hiss::Hiss.generate_coefficients(requiredPiecesToDecode, prime), prime)

    pieces.each { |piece| expect(piece[1]).to be <= prime }
    calculatedSecret = Hiss::Hiss.interpolate_secret(n_random_items_from(pieces, requiredPiecesToDecode), prime)
    expect(calculatedSecret).to eq(secret)
  end

  def roundtrip_buffer(secret)
    numberOfPieces = 8
    requiredPiecesToDecode = 5
    prime = 5717

    pieces = Hiss::Hiss.generate_buffer(secret, numberOfPieces, requiredPiecesToDecode, prime) do |progress|
      yield progress if block_given?
    end

    return Hiss::Hiss.interpolate_buffer(n_random_items_from(pieces, requiredPiecesToDecode), prime) do |progress|
      yield progress if block_given?
    end
  end

  it "successfully roundtrips a random buffer" do
    secret = (1..32).collect{ Random.rand(256) }
    calculatedSecret = roundtrip_buffer(secret)
    expect(calculatedSecret).to eq(secret)
  end

  def roundtrip_string(secret)
    numberOfPieces = 8
    requiredPiecesToDecode = 5

    hiss = Hiss::Hiss.new(secret, numberOfPieces, requiredPiecesToDecode)
    pieces, prime = hiss.generate() do |progress|
      yield progress if block_given?
    end

    return Hiss::Hiss.interpolate_string(n_random_items_from(pieces, requiredPiecesToDecode), prime) do |progress|
      yield progress if block_given?
    end
  end

  it "successfully roundtrips a random string" do
    secret = (1..32).collect{ Random.rand(256) }.pack(Hiss::PACK_FORMAT)
    calculatedSecret = roundtrip_string(secret)
    expect(calculatedSecret).to eq(secret)
  end

  it "successfully roundtrips a file" do
    dataDirectory = Pathname.new(__FILE__).parent.join('testData')
    input = dataDirectory.join('testInput').to_s()
    outputPath = dataDirectory.join('testOutput')
    totalPieces = 8
    requiredPieces = 5
    prime = 5717

    outputPath.delete() if outputPath.exist?
    expect(outputPath.exist?).to eq(false)

    pieces = Hiss::Hiss.generate_file(input, totalPieces, requiredPieces, prime)
    pieces.each{ |piece| expect(Pathname.new(piece).exist?).to eq(true) }

    Hiss::Hiss.interpolate_file(n_random_items_from(pieces, requiredPieces), outputPath.to_s())
    expect(outputPath.exist?).to eq(true)

    inputData = nil
    outputData = nil

    File.open(input){ |file| inputData = file.read() }
    File.open(outputPath.to_s()){ |file| outputData = file.read() }

    expect(outputData).to eq(inputData)
  end

  it "reports progress for buffers" do
    secret = (1..32).collect{ Random.rand(256) }
    progressCallbacks = 0
    roundtrip_buffer(secret){ progressCallbacks+=1 }
    expect(progressCallbacks).to eq(secret.length * 2)
  end

  it "reports progress for strings" do
    secret = (1..32).collect{ Random.rand(256) }.pack(Hiss::PACK_FORMAT)
    progressCallbacks = 0
    roundtrip_string(secret){ progressCallbacks+=1 }
    expect(progressCallbacks).to eq(secret.length * 2)
  end

  it "reports progress for files" do
    dataDirectory = Pathname.new(__FILE__).parent.join('testData')
    inputPath = dataDirectory.join('testInput')
    outputPath = dataDirectory.join('testOutput')
    totalPieces = 5
    requiredPieces = 8
    prime = 5717
    progressCallbacks = 0

    pieces = Hiss::Hiss.generate_file(inputPath.to_s(), totalPieces, requiredPieces, prime){ progressCallbacks += 1 }
    Hiss::Hiss.interpolate_file(pieces, outputPath.to_s()){ progressCallbacks += 1 }

    expect(progressCallbacks).to eq(inputPath.size * 2)
  end

  it "validates single inputs" do
    testData = [
        [[[1, 1], [2, 2]], 5717],                    # Not enough points
        [[[1, 50001], [2, 20000], [3, 30000]], 5717] # Prime too small for y-values
    ]
    testData.each{ |testDatum|
      expect{ Hiss::Hiss.interpolate_secret(testDatum[0], testDatum[1]) }.to raise_exception(RuntimeError)
    }
  end

  it "validates buffers" do
    secret = (1..32).collect{ Random.rand(256) }
    prime = 5717
    buffers = Hiss::Hiss.generate_buffer(secret, 5, 3, prime)
    malformedBuffer = buffers.collect{ |buffer| buffer.clone() }
    malformedBuffer[0].slice!(1)
    mismatchingBuffer = buffers.collect{ |buffer| buffer.clone() }
    mismatchingBuffer[0][1].slice!(1)
    testData = [
        malformedBuffer,      # Malformed input
        mismatchingBuffer     # Mismatching lengths
    ]
    testData.each{ |testDatum|
      expect{ Hiss::Hiss.interpolate_buffer(testDatum, prime) }.to raise_exception(RuntimeError)
    }
  end

  it "validates files" do
    dataDirectory = Pathname.new(__FILE__).parent.join('testData')
    input = dataDirectory.join('testInput').to_s()
    output = dataDirectory.join('testOutput').to_s()
    totalPieces = 5
    requiredPieces = 8
    prime = 5717

    pieces = Hiss::Hiss.generate_file(input, totalPieces, requiredPieces, prime)

    testData = [
        pieces + [dataDirectory.join('testInput-differingPrime.shard')], # Differing prime
        pieces + [pieces[0]]                                             # Duplicated index
    ]
    testData.each{ |testDatum|
      expect{ Hiss::Hiss.interpolate_file(testDatum, output) }.to raise_exception(RuntimeError)
    }
  end
end
