require "rails_helper"

RSpec.describe UserPasswordAttemptLimiter, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:email) { "Teacher@Example.com" }
  let(:remote_ip) { "203.0.113.10" }
  let(:limiter) { described_class.new(email: email, remote_ip: remote_ip, cache: cache) }

  it "blocks on the fifth failure for the normalized email and IP" do
    4.times { expect(limiter.record_failure).to eq(false) }

    expect(limiter.record_failure).to eq(true)
    expect(limiter).to be_blocked
    expect(described_class.new(email: " teacher@example.COM ", remote_ip: remote_ip, cache: cache)).to be_blocked
  end

  it "keeps emails and IPs separate" do
    5.times { limiter.record_failure }

    expect(described_class.new(email: "other@example.com", remote_ip: remote_ip, cache: cache)).not_to be_blocked
    expect(described_class.new(email: email, remote_ip: "203.0.113.11", cache: cache)).not_to be_blocked
  end

  it "keeps the same teacher login ID in different schools separate" do
    first = described_class.new(
      school_id: 1,
      login_id: " TEACHER1 ",
      remote_ip: remote_ip,
      cache: cache
    )
    5.times { first.record_failure }

    same_school = described_class.new(
      school_id: 1,
      login_id: "teacher1",
      remote_ip: remote_ip,
      cache: cache
    )
    other_school = described_class.new(
      school_id: 2,
      login_id: "teacher1",
      remote_ip: remote_ip,
      cache: cache
    )

    expect(same_school).to be_blocked
    expect(other_school).not_to be_blocked
  end

  it "separates teacher failures by credential generation" do
    old_generation = described_class.new(
      school_id: 1,
      login_id: "teacher1",
      credential_generation: "old-encrypted-password",
      remote_ip: remote_ip,
      cache: cache
    )
    5.times { old_generation.record_failure }

    new_generation = described_class.new(
      school_id: 1,
      login_id: "teacher1",
      credential_generation: "new-encrypted-password",
      remote_ip: remote_ip,
      cache: cache
    )

    expect(old_generation).to be_blocked
    expect(new_generation).not_to be_blocked
    5.times { new_generation.record_failure }
    expect(new_generation).to be_blocked
  end

  it "uses a stable generation for unknown teacher login IDs" do
    first = described_class.new(
      school_id: 1,
      login_id: "missing",
      remote_ip: remote_ip,
      cache: cache
    )
    5.times { first.record_failure }

    second = described_class.new(
      school_id: 1,
      login_id: "missing",
      remote_ip: remote_ip,
      cache: cache
    )

    expect(second).to be_blocked
  end

  it "resets failure and block records" do
    5.times { limiter.record_failure }

    limiter.reset

    expect(limiter).not_to be_blocked
    4.times { expect(limiter.record_failure).to eq(false) }
  end

  it "expires the block ten minutes after the fifth failure" do
    travel_to Time.zone.local(2026, 8, 18, 10, 0, 0) do
      5.times { limiter.record_failure }
      expect(limiter).to be_blocked
    end

    travel_to Time.zone.local(2026, 8, 18, 10, 10, 1) do
      expect(limiter).not_to be_blocked
    end
  end

  it "does not include the raw email or IP in cache keys" do
    expect(limiter.cache_key).not_to include(email)
    expect(limiter.cache_key).not_to include(email.downcase)
    expect(limiter.cache_key).not_to include(remote_ip)
    expect(limiter.block_key).not_to include(email)
    expect(limiter.block_key).not_to include(email.downcase)
    expect(limiter.block_key).not_to include(remote_ip)
  end

  it "does not include the raw teacher credential generation in cache keys" do
    generation = "raw-encrypted-password"
    teacher_limiter = described_class.new(
      school_id: 1,
      login_id: "teacher1",
      credential_generation: generation,
      remote_ip: remote_ip,
      cache: cache
    )

    expect(teacher_limiter.cache_key).not_to include(generation)
    expect(teacher_limiter.block_key).not_to include(generation)
  end
end
