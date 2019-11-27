RSpec.describe Hiss do
  it "has a version number" do
    expect(Hiss::VERSION).not_to be nil
  end

  it "does something useful" do
    hiss = Hiss::Hiss.new()
    hiss.generate_points()
  end
end
