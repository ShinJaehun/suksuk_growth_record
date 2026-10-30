require "rails_helper"

RSpec.describe StudentGrowthHelper, type: :helper do
  it "sizes scores and fractional averages on the same bounded, strictly increasing scale" do
    values = [1, 2, 2.5, 3, 4, 5]
    radii = values.map { |value| helper.growth_calendar_bubble_radius(value) }

    expect(radii.each_cons(2).all? { |left, right| left < right }).to be(true)
    expect(radii.first).to be > 0
    expect(radii.last).to be < 50
  end
end
