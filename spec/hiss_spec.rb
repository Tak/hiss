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

    pieces, _ = Hiss::Hiss.generate_points(secret, numberOfPieces, coefficients, prime)

    expect(pieces.length).to eq(6)
    pieces.each_with_index { |piece, index|
      expect(piece[0]).to eq(index + 1)
      expect(piece[1]).to eq(expected_y_values[index])
    }
  end

  def n_random_items_from(array, n)
    indices = (0..(array.length - 1)).collect().to_a()
    (1..n).collect do
      array[indices.slice!(Random.rand() % indices.length)]
    end
  end

  it "successfully roundtrips" do
    secret = Random.rand(2 ** 16)
    numberOfPieces = 8
    requiredPiecesToDecode = 5
    hiss = Hiss::Hiss.new(secret, numberOfPieces, requiredPiecesToDecode)

    pieces, prime = hiss.generate()
    expect(prime).to be >= secret

    pieces.each { |piece| expect(piece[1]).to be <= prime }
    calculatedSecret = Hiss::Hiss.interpolate_secret(n_random_items_from(pieces, requiredPiecesToDecode), prime)
    expect(calculatedSecret).to eq(secret)
  end
end
