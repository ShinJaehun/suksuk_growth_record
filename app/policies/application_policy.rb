class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def admin?
    user.is_a?(User) && user.admin?
  end

  def teacher?
    user.is_a?(User) && user.active_teacher?
  end

  def student?
    user.is_a?(Student) || (user.is_a?(User) && user.student?)
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.none
    end

    private

    def admin?
      user.is_a?(User) && user.admin?
    end

    def teacher?
      user.is_a?(User) && user.active_teacher?
    end

    def student?
      user.is_a?(Student) || (user.is_a?(User) && user.student?)
    end
  end
end
