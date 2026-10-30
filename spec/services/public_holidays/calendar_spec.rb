require "rails_helper"

RSpec.describe PublicHolidays::Calendar do
  let(:client) { instance_double(PublicHolidays::KasiClient) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:holidays) { [{ date: Date.new(2026, 3, 2), name: "대체공휴일", source: "kasi_special_days" }] }

  it "caches the reused API client's annual results without database persistence" do
    expect(client).to receive(:fetch_year).with(2026).once.and_return(holidays)

    2.times do
      expect(described_class.for_year(2026, client: client, cache: cache)).to eq(holidays)
    end
  end

  it "returns unavailable for missing credentials, API errors, or empty results without caching failures" do
    allow(client).to receive(:fetch_year).with(2026)
      .and_raise(PublicHolidays::KasiClient::ConfigurationError)
    expect(described_class.for_year(2026, client: client, cache: cache)).to be_nil

    allow(client).to receive(:fetch_year).with(2026)
      .and_raise(PublicHolidays::KasiClient::ResponseError)
    expect(described_class.for_year(2026, client: client, cache: cache)).to be_nil

    allow(client).to receive(:fetch_year).with(2026).and_return([])
    expect(described_class.for_year(2026, client: client, cache: cache)).to be_nil

    allow(client).to receive(:fetch_year).with(2026).and_return(holidays)
    expect(described_class.for_year(2026, client: client, cache: cache)).to eq(holidays)
  end
end
