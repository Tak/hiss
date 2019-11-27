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

  def n_random_items_from(array, n)
    indices = (0..(array.length - 1)).collect().to_a()
    (1..n).collect do
      array[indices.slice!(Random.rand(indices.length))]
    end
  end

  it "successfully roundtrips a single value" do
    secret = Random.rand(2 ** 16)
    numberOfPieces = 8
    requiredPiecesToDecode = 5
    prime = Prime::detect{ |n| n > secret }

    pieces = Hiss::Hiss.generate_points(secret, numberOfPieces, Hiss::Hiss.generate_coefficients(requiredPiecesToDecode, prime), prime)

    pieces.each { |piece| expect(piece[1]).to be <= prime }
    calculatedSecret = Hiss::Hiss.interpolate_secret(n_random_items_from(pieces, requiredPiecesToDecode), prime)
    expect(calculatedSecret).to eq(secret)
  end

  it "successfully roundtrips a buffer" do
    secret = (1..32).collect{ Random.rand(256) }
    numberOfPieces = 8
    requiredPiecesToDecode = 5
    hiss = Hiss::Hiss.new(secret, numberOfPieces, requiredPiecesToDecode)

    pieces, prime = hiss.generate()

    calculatedSecret = Hiss::Hiss.interpolate_buffer(n_random_items_from(pieces, requiredPiecesToDecode), prime)
    expect(calculatedSecret).to eq(secret)
  end
end
