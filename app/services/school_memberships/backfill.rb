module SchoolMemberships
  class Backfill
    Result = Data.define(:created, :skipped, :conflicts)

    def self.call
      created = 0
      skipped = 0
      conflicts = 0

      Classroom.where.not(teacher_id: nil).includes(:teacher, :school).find_each do |classroom|
        result = EnsureForTeacher.call(
          teacher: classroom.teacher,
          school: classroom.school
        )
        case result
        when :created then created += 1
        when :conflict then conflicts += 1
        else skipped += 1
        end
      end

      Result.new(created:, skipped:, conflicts:)
    end
  end
end
