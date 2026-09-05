require 'rails_helper'

RSpec.describe SchoolYear, type: :model do
  def insert_school_year!(school:, year:, status: 'planning')
    now = Time.current

    described_class.insert!({
                              school_id: school.id,
                              year: year,
                              status: status,
                              created_at: now,
                              updated_at: now
                            })
  end

  describe 'associations' do
    it 'belongs to a school and is exposed through that school' do
      school = create(:school)
      first_year = create(:school_year, school: school, year: 2025, status: 'archived')
      second_year = create(:school_year, school: school, year: 2026)

      expect(first_year.school).to eq(school)
      expect(school.school_years).to contain_exactly(first_year, second_year)
    end

    it 'requires a school' do
      school_year = build(:school_year, school: nil)

      expect(school_year).not_to be_valid
      expect(school_year.errors[:school]).to be_present
    end

    it 'prevents deleting a school that has school years' do
      school = create(:school)
      create(:school_year, school: school)

      expect { school.destroy }.not_to change(described_class, :count)
      expect(school).not_to be_destroyed
    end
  end

  describe 'year' do
    it 'accepts the supported boundaries' do
      expect(build(:school_year, year: 1000)).to be_valid
      expect(build(:school_year, year: 9999)).to be_valid
    end

    it 'rejects years outside the supported boundaries' do
      [999, 10_000].each do |year|
        school_year = build(:school_year, year: year)

        expect(school_year).not_to be_valid
        expect(school_year.errors[:year]).to be_present
      end
    end

    it 'rejects the same year within one school' do
      school = create(:school)
      create(:school_year, school: school, year: 2026)
      duplicate = build(:school_year, school: school, year: 2026, status: 'archived')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:year]).to be_present
    end

    it 'allows the same year in different schools' do
      create(:school_year, year: 2026)

      expect(build(:school_year, year: 2026)).to be_valid
    end
  end

  describe 'status' do
    it 'accepts planning, active, and archived' do
      %w[planning active archived].each do |status|
        expect(build(:school_year, status: status)).to be_valid
      end
    end

    it 'rejects an unsupported status' do
      school_year = build(:school_year, status: 'draft')

      expect(school_year).not_to be_valid
      expect(school_year.errors[:status]).to be_present
    end

    it 'defaults to planning' do
      school_year = described_class.create!(school: create(:school), year: 2026)

      expect(school_year).to be_planning
    end
  end

  describe 'status cardinality' do
    it 'allows one active year per school and rejects a second' do
      school = create(:school)
      create(:school_year, :active, school: school, year: 2025)
      duplicate = build(:school_year, :active, school: school, year: 2026)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:status]).to be_present
    end

    it 'allows active years in different schools' do
      create(:school_year, :active, year: 2026)

      expect(build(:school_year, :active, year: 2026)).to be_valid
    end

    it 'allows one planning year per school and rejects a second' do
      school = create(:school)
      create(:school_year, school: school, year: 2026)
      duplicate = build(:school_year, school: school, year: 2027)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:status]).to be_present
    end

    it 'allows planning years in different schools' do
      create(:school_year, year: 2026)

      expect(build(:school_year, year: 2026)).to be_valid
    end

    it 'allows multiple archived years in one school' do
      school = create(:school)
      first_year = create(:school_year, :archived, school: school, year: 2024)
      second_year = create(:school_year, :archived, school: school, year: 2025)

      expect(school.school_years).to contain_exactly(first_year, second_year)
    end
  end

  describe 'database constraints' do
    it 'rejects duplicate years within one school' do
      school = create(:school)
      insert_school_year!(school: school, year: 2026, status: 'archived')

      expect do
        insert_school_year!(school: school, year: 2026, status: 'active')
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'rejects a second active year within one school' do
      school = create(:school)
      insert_school_year!(school: school, year: 2025, status: 'active')

      expect do
        insert_school_year!(school: school, year: 2026, status: 'active')
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'rejects a second planning year within one school' do
      school = create(:school)
      insert_school_year!(school: school, year: 2026)

      expect do
        insert_school_year!(school: school, year: 2027)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'rejects an unsupported status' do
      expect do
        insert_school_year!(school: create(:school), year: 2026, status: 'draft')
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'rejects a year outside the supported boundaries' do
      expect do
        insert_school_year!(school: create(:school), year: 999)
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
