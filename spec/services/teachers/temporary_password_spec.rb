require "rails_helper"

RSpec.describe Teachers::TemporaryPassword do
  it "generates exactly eight characters from the unambiguous alphabet" do
    password = described_class.generate(login_id: "teacher")

    expect(password.length).to eq(8)
    expect(password).to match(/\A[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}\z/)
    expect(password).not_to match(/[IO01]/)
  end

  it "retries a candidate matching the login ID regardless of case" do
    candidates = "ABCDEFGH23456789"
    indices = candidates.chars.map { |character| described_class::CHARACTERS.index(character) }
    allow(SecureRandom).to receive(:random_number).with(described_class::CHARACTERS.length)
      .and_return(*indices)

    expect(described_class.generate(login_id: "aBcDeFgH")).to eq("23456789")
  end
end
