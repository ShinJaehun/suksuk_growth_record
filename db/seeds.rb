# frozen_string_literal: true

# 개발 및 테스트 환경용 기본 데이터
#
# 새 데이터베이스:
#   bin/rails db:setup
#
# 기존 데이터베이스:
#   bin/rails db:seed
#
# 새 구조를 기준으로 여러 번 실행해도 같은 기본 데이터를 재사용하도록 작성한다.

unless Rails.env.development? || Rails.env.test?
  puts 'Demo seeds are only available in development and test environments.'
  return
end

demo_password = 'password'
demo_student_pin = '1234'

def existing_seed_avatar_keys(keys)
  keys.select do |key|
    Rails.root.join("app/assets/images/avatars/#{key}.png").exist?
  end
end

def first_seed_avatar_key(gender, fallback)
  existing_seed_avatar_keys(User.avatar_keys_for(gender)).first || fallback
end

def seed_student_avatar_key(gender, index)
  available_keys = existing_seed_avatar_keys(Student.avatar_keys_for(gender))
  return if available_keys.empty?

  available_keys[index % available_keys.length]
end

def seed_admin!(
  email:,
  name:,
  password:,
  avatar_key:
)
  admin = User.find_or_initialize_by(
    role: 'admin',
    email: email
  )

  admin.assign_attributes(
    name: name,
    role: 'admin',
    avatar_key: avatar_key,
    password: password,
    password_confirmation: password
  )

  admin.save!
  admin
end

def seed_teacher!(
  school_year:,
  login_id:,
  name:,
  school_role:,
  grade:,
  password:,
  gender:,
  avatar_key:
)
  teacher = User.find_or_initialize_by(
    role: 'teacher',
    school_year: school_year,
    login_id: login_id
  )

  teacher.assign_attributes(
    name: name,
    role: 'teacher',
    school_year: school_year,
    login_id: login_id,
    school_role: school_role,
    grade: grade,
    gender: gender,
    avatar_key: avatar_key,
    password: password,
    password_confirmation: password
  )

  teacher.save!
  teacher
end

def seed_students!(
  classroom:,
  count:,
  name_prefix:,
  student_pin:
)
  gender_indexes = {
    'boy' => 0,
    'girl' => 0
  }

  count.times.map do |index|
    student_number = index + 1
    gender = index.even? ? 'boy' : 'girl'
    avatar_index = gender_indexes.fetch(gender)

    gender_indexes[gender] += 1

    student = Student.find_or_initialize_by(
      classroom: classroom,
      student_number: student_number
    )

    student.assign_attributes(
      name: "#{name_prefix} 학생 #{format('%02d', student_number)}",
      active: true,
      gender: gender,
      avatar_key: seed_student_avatar_key(gender, avatar_index),
      student_pin: student_pin
    )

    student.save!
    student
  end
end

puts '== 관리자 계정 생성 =='

seed_admin!(
  email: 'a@a',
  name: '개발 관리자',
  password: demo_password,
  avatar_key: 'admin'
)

puts '== 학교 생성 =='

school = School.find_or_initialize_by(
  name: '쑥쑥초등학교'
)

school.save!

puts '== 학년도 생성 =='

school_year = school.school_years.active.first_or_initialize

school_year.year ||= if Date.current.month < 3
                       Date.current.year - 1
                     else
                       Date.current.year
                     end

school_year.save!

puts '== 교사 계정 생성 =='

school_manager = seed_teacher!(
  school_year: school_year,
  login_id: 'manager',
  name: '학교 관리자 교사',
  school_role: 'manager',
  grade: 4,
  password: demo_password,
  gender: 'male',
  avatar_key: first_seed_avatar_key(
    'male',
    'teacherM01'
  )
)

classroom_teacher = seed_teacher!(
  school_year: school_year,
  login_id: 'teacher',
  name: '4학년 1반 담임',
  school_role: 'member',
  grade: 4,
  password: demo_password,
  gender: 'female',
  avatar_key: first_seed_avatar_key(
    'female',
    'teacherF01'
  )
)

puts '== 교실 생성 =='

classroom = Classroom.find_or_initialize_by(
  school_year: school_year,
  grade: 4,
  class_label: '1'
)

classroom.save!

empty_classroom = Classroom.find_or_initialize_by(
  school_year: school_year,
  grade: 4,
  class_label: '2'
)

empty_classroom.save!

puts '== 교실 담당 교사 배정 =='

HomeroomAssignment.find_or_create_by!(
  classroom: classroom,
  ended_on: nil
) do |assignment|
  assignment.teacher = classroom_teacher
  assignment.started_on = Date.current
end

HomeroomAssignment.find_or_create_by!(
  classroom: empty_classroom,
  ended_on: nil
) do |assignment|
  assignment.teacher = school_manager
  assignment.started_on = Date.current
end

puts '== 학생 25명 생성 =='

students = seed_students!(
  classroom: classroom,
  count: 25,
  name_prefix: '4-1',
  student_pin: demo_student_pin
)

puts
puts '========================================'
puts 'Seed 데이터 생성 완료'
puts '========================================'
puts
puts '관리자'
puts '  이메일: a@a'
puts "  비밀번호: #{demo_password}"
puts
puts '학교 관리자 교사'
puts "  학교: #{school.name}"
puts "  학년도: #{school_year.year}"
puts '  로그인 ID: manager'
puts "  비밀번호: #{demo_password}"
puts
puts '담임 교사'
puts "  학교: #{school.name}"
puts "  학년도: #{school_year.year}"
puts '  로그인 ID: teacher'
puts "  비밀번호: #{demo_password}"
puts
puts '학생'
puts "  학교: #{school.name}"
puts "  교실: #{classroom.grade}학년 #{classroom.class_label}반"
puts "  인원: #{students.count}명"
puts "  PIN: #{demo_student_pin}"
puts
puts '학생 로그인 토큰'
puts "  #{classroom.student_login_token}"
puts
