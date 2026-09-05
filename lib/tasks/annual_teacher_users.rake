require "csv"

namespace :annual_teacher_users do
  desc "Audit or reconcile annual teacher fields before Phase 2C cutover"
  task cutover_readiness: :environment do
    dry_run_value = ENV.fetch("DRY_RUN", "true")
    abort "DRY_RUN must be true or false." unless %w[true false].include?(dry_run_value)

    result = AnnualTeacherUsers::CutoverReadiness.call(dry_run: dry_run_value == "true")
    result.issues.each { |issue| warn "error #{issue}" }
    puts [
      "ready=#{result.ready?}",
      "dry_run=#{result.dry_run}",
      "reconciled=#{result.reconciled_count}",
      "normalized=#{result.normalized_count}"
    ].join(" ")
    abort "Annual teacher cutover is not ready." unless result.ready?
  end

  desc "Map existing teachers to an explicit active SchoolYear"
  task map_existing: :environment do
    school_year_id = ENV.fetch("SCHOOL_YEAR_ID")
    csv_path = ENV.fetch("CSV_PATH")
    dry_run_value = ENV.fetch("DRY_RUN", "false")
    unless %w[true false].include?(dry_run_value)
      abort "DRY_RUN must be true or false."
    end

    table = CSV.read(csv_path, headers: true)
    required_headers = %w[teacher_user_id login_id]
    unless table.headers == required_headers
      abort "CSV headers must be: #{required_headers.join(",")}"
    end

    rows = table.map do |row|
      {
        teacher_user_id: row["teacher_user_id"],
        login_id: row["login_id"]
      }
    end
    result = AnnualTeacherUsers::MappingBackfill.call(
      target_school_year_id: school_year_id,
      rows:,
      dry_run: dry_run_value == "true"
    )

    result.warnings.each { |warning| warn "warning #{warning}" }
    unless result.success?
      result.errors.each { |error| warn "error #{error}" }
      abort "Annual teacher mapping failed."
    end

    puts [
      "dry_run=#{result.dry_run}",
      "school_year_id=#{result.target_school_year_id}",
      "school_id=#{result.school_id}",
      "requested=#{result.requested_count}",
      "mapped=#{result.mapped_count}",
      "already_mapped=#{result.already_mapped_count}"
    ].join(" ")
  rescue KeyError => error
    abort "Missing required input: #{error.key}"
  rescue Errno::ENOENT, Errno::EACCES, CSV::MalformedCSVError => error
    abort "Could not read mapping CSV: #{error.message}"
  end
end
