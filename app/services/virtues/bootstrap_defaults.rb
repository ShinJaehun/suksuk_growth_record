module Virtues
  class BootstrapDefaults
    DEFAULT_NAMES = %w[독서 봉사 감사].freeze

    def self.call(classroom:)
      classroom.with_lock do
        return if classroom.virtues.exists?

        DEFAULT_NAMES.each_with_index do |name, index|
          classroom.virtues.create!(name: name, active: true, position: index + 1)
        end
      end
    end
  end
end
